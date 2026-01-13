"""
Async Task Manager for CrateBot API.
Handles long-running tasks like training and batch tagging.
"""
import asyncio
import uuid
import logging
from datetime import datetime
from typing import Dict, Optional, Callable, Any, List, Set
from dataclasses import dataclass, field
from enum import Enum
from concurrent.futures import ThreadPoolExecutor
import threading
import queue

logger = logging.getLogger(__name__)


class TaskStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"
    PAUSED = "paused"


@dataclass
class TaskProgress:
    """Current progress of a task."""
    phase: str = "idle"
    progress: float = 0.0  # 0-100
    current_item: Optional[str] = None
    current_index: int = 0
    total_items: int = 0
    message: Optional[str] = None
    metrics: Dict[str, Any] = field(default_factory=dict)


@dataclass
class Task:
    """A long-running task."""
    task_id: str
    task_type: str  # "training", "tagging", "vibe"
    status: TaskStatus = TaskStatus.PENDING
    progress: TaskProgress = field(default_factory=TaskProgress)
    result: Optional[Any] = None
    error: Optional[str] = None
    created_at: datetime = field(default_factory=datetime.utcnow)
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    cancel_requested: bool = False
    pause_requested: bool = False
    log_messages: List[str] = field(default_factory=list)


class TaskManager:
    """
    Manages async tasks with progress tracking.

    Uses a ThreadPoolExecutor to run CPU-bound Python tasks
    (audio analysis, training) without blocking the event loop.
    """

    def __init__(self, max_workers: int = 2):
        self.tasks: Dict[str, Task] = {}
        self.executor = ThreadPoolExecutor(max_workers=max_workers)
        self.progress_callbacks: Dict[str, List[Callable]] = {}
        self.async_queues: Dict[str, Set[asyncio.Queue]] = {}  # For WebSocket updates
        self._lock = threading.Lock()
        self._event_loop: Optional[asyncio.AbstractEventLoop] = None

    def create_task(self, task_type: str) -> str:
        """Create a new task and return its ID."""
        task_id = str(uuid.uuid4())[:12]
        task = Task(task_id=task_id, task_type=task_type)

        with self._lock:
            self.tasks[task_id] = task
            self.progress_callbacks[task_id] = []
            self.async_queues[task_id] = set()

        logger.info(f"Created task {task_id} of type {task_type}")
        return task_id

    def get_task(self, task_id: str) -> Optional[Task]:
        """Get a task by ID."""
        return self.tasks.get(task_id)

    def list_tasks(self, task_type: Optional[str] = None) -> List[Task]:
        """List all tasks, optionally filtered by type."""
        tasks = list(self.tasks.values())
        if task_type:
            tasks = [t for t in tasks if t.task_type == task_type]
        return sorted(tasks, key=lambda t: t.created_at, reverse=True)

    def update_progress(
        self,
        task_id: str,
        phase: Optional[str] = None,
        progress: Optional[float] = None,
        current_item: Optional[str] = None,
        current_index: Optional[int] = None,
        total_items: Optional[int] = None,
        message: Optional[str] = None,
        metrics: Optional[Dict[str, Any]] = None,
    ) -> None:
        """Update task progress and notify callbacks."""
        task = self.tasks.get(task_id)
        if not task:
            return

        if phase is not None:
            task.progress.phase = phase
        if progress is not None:
            task.progress.progress = progress
        if current_item is not None:
            task.progress.current_item = current_item
        if current_index is not None:
            task.progress.current_index = current_index
        if total_items is not None:
            task.progress.total_items = total_items
        if message is not None:
            task.progress.message = message
            task.log_messages.append(f"[{datetime.utcnow().isoformat()}] {message}")
        if metrics is not None:
            task.progress.metrics.update(metrics)

        # Notify progress callbacks
        self._notify_progress(task_id, task)

    def add_log(self, task_id: str, message: str) -> None:
        """Add a log message to the task."""
        task = self.tasks.get(task_id)
        if task:
            timestamp = datetime.utcnow().isoformat()
            task.log_messages.append(f"[{timestamp}] {message}")

    def _notify_progress(self, task_id: str, task: Task) -> None:
        """Notify all progress callbacks for a task."""
        callbacks = self.progress_callbacks.get(task_id, [])
        for callback in callbacks:
            try:
                callback(task)
            except Exception as e:
                logger.error(f"Progress callback error: {e}")

        # Push to async queues for WebSocket subscribers
        queues = self.async_queues.get(task_id, set())
        if queues and self._event_loop:
            # Create update dict for serialization
            update = {
                "task_id": task.task_id,
                "status": task.status.value,
                "progress": task.progress.progress,
                "phase": task.progress.phase,
                "current_item": task.progress.current_item,
                "current_index": task.progress.current_index,
                "total_items": task.progress.total_items,
                "message": task.progress.message,
            }
            for q in list(queues):
                try:
                    # Use call_soon_threadsafe since this may be called from thread pool
                    self._event_loop.call_soon_threadsafe(q.put_nowait, update)
                except Exception as e:
                    logger.debug(f"Failed to push to async queue: {e}")

    def subscribe_progress(self, task_id: str, callback: Callable[[Task], None]) -> None:
        """Subscribe to progress updates for a task."""
        with self._lock:
            if task_id in self.progress_callbacks:
                self.progress_callbacks[task_id].append(callback)

    def unsubscribe_progress(self, task_id: str, callback: Callable[[Task], None]) -> None:
        """Unsubscribe from progress updates."""
        with self._lock:
            if task_id in self.progress_callbacks:
                try:
                    self.progress_callbacks[task_id].remove(callback)
                except ValueError:
                    pass

    def subscribe_async(self, task_id: str, q: asyncio.Queue) -> None:
        """Subscribe an asyncio queue for real-time updates (for WebSocket)."""
        with self._lock:
            if task_id not in self.async_queues:
                self.async_queues[task_id] = set()
            self.async_queues[task_id].add(q)

    def unsubscribe_async(self, task_id: str, q: asyncio.Queue) -> None:
        """Unsubscribe an asyncio queue."""
        with self._lock:
            if task_id in self.async_queues:
                self.async_queues[task_id].discard(q)

    async def run_task(
        self,
        task_id: str,
        func: Callable,
        *args,
        **kwargs
    ) -> Any:
        """
        Run a synchronous function in the thread pool.

        The function should accept a progress_callback keyword argument
        for reporting progress updates.
        """
        task = self.tasks.get(task_id)
        if not task:
            raise ValueError(f"Task {task_id} not found")

        task.status = TaskStatus.RUNNING
        task.started_at = datetime.utcnow()

        # Capture event loop for async queue notifications
        loop = asyncio.get_event_loop()
        self._event_loop = loop

        # Create progress callback for the function
        def progress_callback(**progress_kwargs):
            self.update_progress(task_id, **progress_kwargs)
            # Check for cancellation
            if task.cancel_requested:
                raise asyncio.CancelledError("Task cancelled by user")
            # Check for pause
            while task.pause_requested:
                import time
                time.sleep(0.5)

        # Add progress callback to kwargs
        kwargs['progress_callback'] = progress_callback

        try:
            # Run CPU-bound task in thread pool
            result = await loop.run_in_executor(
                self.executor,
                lambda: func(*args, **kwargs)
            )

            task.status = TaskStatus.COMPLETED
            task.result = result
            task.completed_at = datetime.utcnow()

            logger.info(f"Task {task_id} completed successfully")
            return result

        except asyncio.CancelledError:
            task.status = TaskStatus.CANCELLED
            task.completed_at = datetime.utcnow()
            logger.info(f"Task {task_id} was cancelled")
            raise

        except Exception as e:
            task.status = TaskStatus.FAILED
            task.error = str(e)
            task.completed_at = datetime.utcnow()
            logger.error(f"Task {task_id} failed: {e}")
            raise

    def cancel_task(self, task_id: str) -> bool:
        """Request cancellation of a task."""
        task = self.tasks.get(task_id)
        if not task:
            return False

        if task.status in (TaskStatus.COMPLETED, TaskStatus.FAILED, TaskStatus.CANCELLED):
            return False

        task.cancel_requested = True
        logger.info(f"Cancellation requested for task {task_id}")
        return True

    def pause_task(self, task_id: str) -> bool:
        """Request pause of a task."""
        task = self.tasks.get(task_id)
        if not task:
            return False

        if task.status != TaskStatus.RUNNING:
            return False

        task.pause_requested = True
        task.status = TaskStatus.PAUSED
        logger.info(f"Pause requested for task {task_id}")
        return True

    def resume_task(self, task_id: str) -> bool:
        """Resume a paused task."""
        task = self.tasks.get(task_id)
        if not task:
            return False

        if task.status != TaskStatus.PAUSED:
            return False

        task.pause_requested = False
        task.status = TaskStatus.RUNNING
        logger.info(f"Task {task_id} resumed")
        return True

    def cleanup_old_tasks(self, max_age_hours: int = 24) -> int:
        """Remove completed/failed tasks older than max_age_hours."""
        cutoff = datetime.utcnow()
        from datetime import timedelta
        cutoff = cutoff - timedelta(hours=max_age_hours)

        to_remove = []
        for task_id, task in self.tasks.items():
            if task.status in (TaskStatus.COMPLETED, TaskStatus.FAILED, TaskStatus.CANCELLED):
                if task.completed_at and task.completed_at < cutoff:
                    to_remove.append(task_id)

        with self._lock:
            for task_id in to_remove:
                del self.tasks[task_id]
                if task_id in self.progress_callbacks:
                    del self.progress_callbacks[task_id]

        logger.info(f"Cleaned up {len(to_remove)} old tasks")
        return len(to_remove)

    def shutdown(self):
        """Shutdown the executor."""
        self.executor.shutdown(wait=True)


# Global task manager instance
task_manager = TaskManager()

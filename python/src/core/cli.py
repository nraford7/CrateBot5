import click
import os
from rich.console import Console
from rich.table import Table
from rich.progress import track
from rich import print as rprint

from .auto_tagger import AutoTagger
from .tag_manager import TagManager
from .audio_analyzer import AudioAnalyzer
from .config import config
from .validators import (
    ValidationError,
    validate_directory,
    validate_file,
    validate_audio_file,
    validate_model_path,
    validate_test_size,
)

console = Console()


@click.group()
def main():
    """CrateBot - Automatic MP3 tagging using audio fingerprinting and machine learning"""
    pass


@main.command()
@click.argument('training_dir', type=click.Path(), required=False)
@click.option('--output', '-o', default='models/cratebot.pkl',
              help='Output path for the trained model')
@click.option('--test-size', '-t', default=0.2, type=float,
              help='Proportion of data to use for testing (0.0-1.0)')
@click.option('--resume', '-r', is_flag=True,
              help='Use tag selections from most recent checkpoint (skip interactive selection)')
def train(training_dir, output, test_size, resume):
    """Train a new tagging model from a directory of tagged MP3s"""
    if training_dir is None:
        training_dir = config.get_last_directory('training_dir')
        if training_dir is None:
            console.print("[bold red]No training directory specified and no previous directory saved.[/bold red]")
            console.print("Usage: cratebot train <directory>")
            return
        console.print(f"[dim]Using last training directory: {training_dir}[/dim]")

    # Validate inputs
    try:
        training_dir = str(validate_directory(training_dir))
        test_size = validate_test_size(test_size)
    except ValidationError as e:
        console.print(f"[bold red]Validation error:[/bold red] {e}")
        return

    config.set_last_directory('training_dir', training_dir)

    console.print(f"[bold green]Training CrateBot Model[/bold green]")
    console.print(f"Training directory: {training_dir}")
    console.print(f"Output model: {output}")
    console.print(f"Test size: {test_size}")
    if resume:
        console.print("[dim]Resume mode: using tag selections from previous checkpoint[/dim]")

    tagger = AutoTagger()

    try:
        if resume:
            results = tagger.train_from_directory_resume(training_dir, output, test_size)
        else:
            results = tagger.train_from_directory(training_dir, output, test_size)

        console.print("\n[bold green]Training Complete![/bold green]")

        table = Table(title="Training Results")
        table.add_column("Metric", style="cyan")
        table.add_column("Value", style="green")

        table.add_row("Training Samples", str(results['training_samples']))
        table.add_row("Features Used", str(results['features_used']))

        if 'genre' in results and results['genre'].get('status') == 'trained':
            table.add_row("Genre Accuracy", f"{results['genre']['accuracy']:.3f}")
            table.add_row("Genre Classes", str(len(results['genre']['classes'])))

        if 'album' in results and results['album'].get('status') == 'trained':
            table.add_row("Album Accuracy", f"{results['album']['accuracy']:.3f}")
            table.add_row("Album Classes", str(len(results['album']['classes'])))

        if 'comments' in results and results['comments'].get('status') == 'trained':
            table.add_row("Comments Avg F1", f"{results['comments']['avg_f1']:.3f}")
            table.add_row("Comment Tags", str(results['comments']['num_labels']))

        if 'comments_synthesis' in results and results['comments_synthesis'].get('status') == 'trained':
            table.add_row("Comments Synthesis MSE", f"{results['comments_synthesis']['mse']:.4f}")
            table.add_row("Synthesis Embedding Dim", str(results['comments_synthesis']['embedding_dim']))

        if 'overall_likeness' in results and results['overall_likeness'].get('status') == 'trained':
            table.add_row("Overall Likeness MSE", f"{results['overall_likeness']['mse']:.4f}")
            table.add_row("Overall Embedding Dim", str(results['overall_likeness']['embedding_dim']))

        console.print(table)

    except Exception as e:
        console.print(f"[bold red]Error during training:[/bold red] {str(e)}")


@main.command()
@click.argument('input_path', type=click.Path(), required=False)
@click.option('--model', '-m', default='models/cratebot.pkl',
              help='Path to the trained model')
@click.option('--recursive', '-r', is_flag=True,
              help='Process directories recursively')
@click.option('--overwrite', '-w', is_flag=True,
              help='Overwrite existing tags')
@click.option('--dry-run', '-d', is_flag=True,
              help='Preview tags without writing them')
@click.option('--report', '-R', type=click.Path(),
              help='Save tagging report to JSON file')
def tag(input_path, model, recursive, overwrite, dry_run, report):
    """Tag MP3 files using a trained model"""
    if input_path is None:
        input_path = config.get_last_directory('input_path')
        if input_path is None:
            console.print("[bold red]No input path specified and no previous path saved.[/bold red]")
            console.print("Usage: cratebot tag <file_or_directory>")
            return
        console.print(f"[dim]Using last input path: {input_path}[/dim]")

    # Validate inputs
    try:
        input_path = str(validate_file(input_path, must_exist=True) if os.path.isfile(input_path)
                        else validate_directory(input_path))
        model = str(validate_model_path(model))
    except ValidationError as e:
        console.print(f"[bold red]Validation error:[/bold red] {e}")
        return

    config.set_last_directory('input_path', input_path)
    
    tagger = AutoTagger(model_path=model)
    
    if os.path.isfile(input_path):
        console.print(f"[bold green]Tagging single file:[/bold green] {input_path}")
        
        if dry_run:
            console.print("[yellow]DRY RUN MODE - Tags will not be written[/yellow]")
        
        try:
            tags = tagger.tag_file(input_path, overwrite=overwrite, dry_run=dry_run)

            table = Table(title="Predicted Tags")
            table.add_column("Tag Type", style="cyan")
            table.add_column("Value", style="green")

            if 'genre' in tags:
                table.add_row("Genre (Timing)", tags['genre'])

            if 'album' in tags:
                table.add_row("Album (Mood)", tags['album'])

            if 'comments' in tags:
                table.add_row("Comments (Character)", tags['comments'])

            console.print(table)

        except Exception as e:
            console.print(f"[bold red]Error:[/bold red] {str(e)}")
    
    else:
        console.print(f"[bold green]Tagging directory:[/bold green] {input_path}")
        
        if recursive:
            console.print("Recursive mode enabled")
        if overwrite:
            console.print("Overwrite mode enabled")
        if dry_run:
            console.print("[yellow]DRY RUN MODE - Tags will not be written[/yellow]")
        
        try:
            results = tagger.tag_directory(
                input_path, 
                recursive=recursive,
                overwrite=overwrite,
                dry_run=dry_run,
                output_report=report
            )
            
            successful = sum(1 for r in results if r['status'] == 'success')
            failed = sum(1 for r in results if r['status'] == 'failed')
            
            console.print(f"\n[bold green]Tagging complete![/bold green]")
            console.print(f"Successfully tagged: {successful} files")
            console.print(f"Failed: {failed} files")
            
            if report:
                console.print(f"Report saved to: {report}")
            
        except Exception as e:
            console.print(f"[bold red]Error:[/bold red] {str(e)}")


@main.command()
@click.argument('mp3_file', type=click.Path())
def analyze(mp3_file):
    """Analyze an MP3 file and display its audio features"""
    try:
        mp3_file = str(validate_audio_file(mp3_file))
    except ValidationError as e:
        console.print(f"[bold red]Validation error:[/bold red] {e}")
        return

    console.print(f"[bold green]Analyzing:[/bold green] {mp3_file}")
    
    analyzer = AudioAnalyzer()
    
    try:
        with console.status("[bold yellow]Extracting audio features..."):
            features = analyzer.extract_features(mp3_file)
        
        table = Table(title="Audio Features")
        table.add_column("Feature", style="cyan")
        table.add_column("Value", style="green")
        
        table.add_row("Tempo (BPM)", f"{features['tempo']:.1f}")
        table.add_row("Spectral Centroid", f"{features['spectral_centroid']:.2f}")
        table.add_row("Spectral Rolloff", f"{features['spectral_rolloff']:.2f}")
        table.add_row("Zero Crossing Rate", f"{features['zero_crossing_rate']:.4f}")
        table.add_row("RMS Energy", f"{features['rms_energy']:.4f}")
        table.add_row("Has Fingerprint", "Yes" if features['fingerprint'] else "No")
        table.add_row("Feature Vector Size", str(len(features['feature_vector'])))
        
        console.print(table)
        
    except Exception as e:
        console.print(f"[bold red]Error:[/bold red] {str(e)}")


@main.command()
@click.argument('mp3_file', type=click.Path())
def read_tags(mp3_file):
    """Read and display existing ID3 tags from an MP3 file"""
    try:
        mp3_file = str(validate_audio_file(mp3_file))
    except ValidationError as e:
        console.print(f"[bold red]Validation error:[/bold red] {e}")
        return

    console.print(f"[bold green]Reading tags from:[/bold green] {mp3_file}")
    
    tag_manager = TagManager()
    
    try:
        tags = tag_manager.read_tags(mp3_file)
        
        if not tags:
            console.print("[yellow]No tags found in file[/yellow]")
            return
        
        table = Table(title="ID3 Tags")
        table.add_column("Tag", style="cyan")
        table.add_column("Value", style="green")

        for key in ['title', 'artist', 'album', 'date', 'genre']:
            if key in tags:
                table.add_row(key.capitalize(), tags[key])

        # Show Composer (vibe tag)
        if 'composer' in tags:
            table.add_row("Composer (Vibe)", tags['composer'])

        # Show Grouping and Category (likeness scores)
        if 'grouping' in tags:
            table.add_row("Grouping (Comment Likeness)", tags['grouping'])
        if 'category' in tags:
            table.add_row("Category (Overall Likeness)", tags['category'])

        if 'comments' in tags:
            comments = tags['comments']
            if isinstance(comments, list):
                comments = " | ".join(comments)
            table.add_row("Comments", comments[:100])

        if 'custom' in tags:
            for key, value in tags['custom'].items():
                table.add_row(f"Custom: {key}", value)

        console.print(table)
        
    except Exception as e:
        console.print(f"[bold red]Error:[/bold red] {str(e)}")


@main.command()
@click.argument('mp3_file1', type=click.Path())
@click.argument('mp3_file2', type=click.Path())
@click.option('--model', '-m', type=click.Path(),
              help='Optional model to load for comparison')
def compare(mp3_file1, mp3_file2, model):
    """Compare audio features and tags between two MP3 files"""
    try:
        mp3_file1 = str(validate_audio_file(mp3_file1))
        mp3_file2 = str(validate_audio_file(mp3_file2))
        if model:
            model = str(validate_model_path(model))
    except ValidationError as e:
        console.print(f"[bold red]Validation error:[/bold red] {e}")
        return

    console.print(f"[bold green]Comparing MP3 files[/bold green]")
    
    if model:
        tagger = AutoTagger(model_path=model)
    else:
        tagger = AutoTagger()
    
    try:
        with console.status("[bold yellow]Analyzing files..."):
            comparison = tagger.analyze_similarity(mp3_file1, mp3_file2)
        
        table = Table(title="Audio Similarity")
        table.add_column("Metric", style="cyan")
        table.add_column("Value", style="green")
        
        table.add_row("File 1", comparison['file1'])
        table.add_row("File 2", comparison['file2'])
        table.add_row("Feature Distance", f"{comparison['feature_distance']:.3f}")
        table.add_row("Similarity Score", f"{comparison['similarity_score']:.3f}")
        
        console.print(table)
        
        if comparison['tags1'] or comparison['tags2']:
            tag_table = Table(title="Tag Comparison")
            tag_table.add_column("Tag", style="cyan")
            tag_table.add_column("File 1", style="yellow")
            tag_table.add_column("File 2", style="green")
            
            all_keys = set()
            if comparison['tags1']:
                all_keys.update(comparison['tags1'].keys())
            if comparison['tags2']:
                all_keys.update(comparison['tags2'].keys())
            
            for key in ['title', 'artist', 'album', 'genre']:
                if key in all_keys:
                    val1 = comparison['tags1'].get(key, '-') if comparison['tags1'] else '-'
                    val2 = comparison['tags2'].get(key, '-') if comparison['tags2'] else '-'
                    tag_table.add_row(key.capitalize(), str(val1)[:40], str(val2)[:40])
            
            console.print(tag_table)
        
    except Exception as e:
        console.print(f"[bold red]Error:[/bold red] {str(e)}")


@main.command()
@click.argument('reference_file', type=click.Path(exists=True))
@click.argument('search_dir', type=click.Path(exists=True))
@click.option('--model', '-m', default='models/cratebot.pkl',
              help='Path to the trained model')
@click.option('--mode', '-M', type=click.Choice(['comments', 'overall']), default='overall',
              help='Similarity mode: comments (character profile) or overall (all tags)')
@click.option('--top', '-n', default=10, type=int,
              help='Number of similar songs to show')
def similar(reference_file, search_dir, model, mode, top):
    """Find songs similar to a reference track based on learned embeddings"""
    from pathlib import Path
    import numpy as np

    if not os.path.exists(model):
        console.print(f"[bold red]Model not found:[/bold red] {model}")
        return

    tagger = AutoTagger(model_path=model)

    console.print(f"[bold green]Finding similar songs[/bold green]")
    console.print(f"Reference: {reference_file}")
    console.print(f"Search directory: {search_dir}")
    console.print(f"Mode: {mode}")

    try:
        # Get reference embedding
        with console.status("[bold yellow]Analyzing reference track..."):
            ref_features = tagger.analyzer.extract_features(reference_file)
            ref_tags = tagger.predictor.predict_tags(ref_features)

        embedding_key = '_comments_embedding' if mode == 'comments' else '_overall_embedding'

        if embedding_key not in ref_tags:
            console.print(f"[bold red]Model doesn't have {mode} embeddings trained[/bold red]")
            return

        ref_embedding = np.array(ref_tags[embedding_key])

        # Find all MP3s in search directory
        search_path = Path(search_dir)
        mp3_files = list(search_path.glob('**/*.mp3'))

        if not mp3_files:
            console.print("[yellow]No MP3 files found in search directory[/yellow]")
            return

        console.print(f"Searching {len(mp3_files)} files...")

        # Calculate similarities
        similarities = []
        for mp3_path in mp3_files:
            if str(mp3_path) == reference_file:
                continue

            try:
                features = tagger.analyzer.extract_features(str(mp3_path))
                tags = tagger.predictor.predict_tags(features)

                if embedding_key in tags:
                    embedding = np.array(tags[embedding_key])
                    distance = np.linalg.norm(ref_embedding - embedding)
                    similarity = 1.0 / (1.0 + distance)

                    similarities.append({
                        'file': str(mp3_path),
                        'name': mp3_path.name,
                        'similarity': similarity,
                        'tags': tags
                    })
            except Exception:
                continue

        # Sort by similarity
        similarities.sort(key=lambda x: -x['similarity'])

        # Display results
        table = Table(title=f"Top {top} Similar Songs ({mode.capitalize()} Similarity)")
        table.add_column("#", style="dim", width=4)
        table.add_column("File", style="cyan")
        table.add_column("Similarity", justify="right", style="green")
        table.add_column("Genre", style="yellow")
        table.add_column("Album", style="magenta")

        for idx, item in enumerate(similarities[:top], 1):
            genre = item['tags'].get('genre', '-')
            album = item['tags'].get('album', '-')
            table.add_row(
                str(idx),
                item['name'][:40],
                f"{item['similarity']:.3f}",
                genre[:15],
                album[:15]
            )

        console.print(table)

    except Exception as e:
        console.print(f"[bold red]Error:[/bold red] {str(e)}")


@main.command()
@click.argument('input_path', type=click.Path(exists=True), required=False)
@click.option('--recursive', '-r', is_flag=True,
              help='Process directories recursively')
@click.option('--overwrite', '-w', is_flag=True,
              help='Overwrite existing composer/vibe tags')
@click.option('--dry-run', '-d', is_flag=True,
              help='Preview vibes without writing them')
@click.option('--report', '-R', type=click.Path(),
              help='Save vibe report to JSON file')
@click.option('--no-hooks', is_flag=True,
              help='Skip vocal hook detection (faster processing)')
def vibe(input_path, recursive, overwrite, dry_run, report, no_hooks):
    """Generate vibe tags using Claude API.

    Analyzes audio features and existing tags to generate a ~5 word
    ALL CAPS description of the track's vibe/feeling.

    Vibes are stored in the Composer (TCOM) ID3 tag.
    Vocal hooks (if detected) are stored in TXXX:HOOK tag.

    Requires ANTHROPIC_API_KEY environment variable to be set.

    Examples:
        cratebot vibe track.mp3
        cratebot vibe ./music -r --overwrite
        cratebot vibe ./library -r --report vibes.json
        cratebot vibe ./music -r --no-hooks  # Skip hook detection

    Example output: "DARK WAREHOUSE PEAK HOUR ENERGY"
    """
    from .vibe_generator import is_vibe_available, get_vibe_status
    from .hook_transcriber import is_hook_transcription_available, get_hook_transcription_status

    # Check availability
    if not is_vibe_available():
        console.print(f"[bold red]Vibe generation unavailable:[/bold red] {get_vibe_status()}")
        console.print("\nTo enable vibe generation:")
        console.print("  1. pip install anthropic")
        console.print("  2. export ANTHROPIC_API_KEY=your-api-key")
        return

    # Show hook detection status
    if not no_hooks:
        if is_hook_transcription_available():
            console.print("[dim]Hook detection: enabled (Whisper ready)[/dim]")
        else:
            console.print(f"[dim]Hook detection: disabled ({get_hook_transcription_status()})[/dim]")

    if input_path is None:
        input_path = config.get_last_directory('input_path')
        if input_path is None:
            console.print("[bold red]No input path specified and no previous path saved.[/bold red]")
            console.print("Usage: cratebot vibe <file_or_directory>")
            return
        console.print(f"[dim]Using last input path: {input_path}[/dim]")

    config.set_last_directory('input_path', input_path)

    tagger = AutoTagger()

    if os.path.isfile(input_path):
        # Single file
        console.print(f"[bold green]Generating vibe for:[/bold green] {input_path}")

        if dry_run:
            console.print("[yellow]DRY RUN MODE - Vibe will not be written[/yellow]")

        try:
            result = tagger.generate_vibe(input_path, overwrite=overwrite, dry_run=dry_run, skip_hook=no_hooks)

            if result['status'] == 'tagged':
                table = Table(title="Generated Vibe")
                table.add_column("Field", style="cyan")
                table.add_column("Value", style="green")
                table.add_row("File", os.path.basename(input_path))
                table.add_row("Vibe", result['vibe'])
                if result.get('hook'):
                    table.add_row("Hook", f"\"{result['hook']}\"")
                table.add_row("Stored In", "Composer (TCOM) + HOOK tags")
                console.print(table)
            elif result['status'] == 'skipped':
                console.print(f"[yellow]Skipped:[/yellow] File already has composer tag: {result.get('vibe', '')}")
                console.print("Use --overwrite to replace existing tags")
            else:
                console.print(f"[bold red]Error:[/bold red] {result.get('error', 'Unknown error')}")

        except Exception as e:
            console.print(f"[bold red]Error:[/bold red] {str(e)}")

    else:
        # Directory
        console.print(f"[bold green]Generating vibes for directory:[/bold green] {input_path}")

        if recursive:
            console.print("Recursive mode enabled")
        if overwrite:
            console.print("Overwrite mode enabled")
        if dry_run:
            console.print("[yellow]DRY RUN MODE - Vibes will not be written[/yellow]")

        try:
            results = tagger.generate_vibes(
                input_path,
                recursive=recursive,
                overwrite=overwrite,
                dry_run=dry_run,
                output_report=report,
                skip_hook=no_hooks
            )

            if results:
                # Show sample of generated vibes
                tagged = [r for r in results if r['status'] == 'tagged']
                if tagged[:5]:
                    console.print("\n[bold]Sample vibes generated:[/bold]")
                    sample_table = Table()
                    sample_table.add_column("File", style="cyan", max_width=40)
                    sample_table.add_column("Vibe", style="green")

                    for r in tagged[:5]:
                        sample_table.add_row(
                            os.path.basename(r['file']),
                            r.get('vibe', '-')
                        )
                    console.print(sample_table)

                if report:
                    console.print(f"\nFull report saved to: {report}")

        except Exception as e:
            console.print(f"[bold red]Error:[/bold red] {str(e)}")


@main.command()
def vibe_status():
    """Check vibe generation availability and status."""
    from .vibe_generator import is_vibe_available, get_vibe_status
    try:
        import anthropic
        has_anthropic = True
    except ImportError:
        has_anthropic = False
    import os

    console.print("[bold]Vibe Generation Status[/bold]\n")

    table = Table()
    table.add_column("Component", style="cyan")
    table.add_column("Status", style="green")

    # Anthropic package
    if has_anthropic:
        table.add_row("anthropic package", "[green]Installed[/green]")
    else:
        table.add_row("anthropic package", "[red]Not installed[/red]")

    # API key
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if api_key:
        masked_key = api_key[:8] + "..." + api_key[-4:] if len(api_key) > 12 else "***"
        table.add_row("ANTHROPIC_API_KEY", f"[green]Set[/green] ({masked_key})")
    else:
        table.add_row("ANTHROPIC_API_KEY", "[red]Not set[/red]")

    # Overall status
    if is_vibe_available():
        table.add_row("Overall", "[bold green]Ready[/bold green]")
    else:
        table.add_row("Overall", f"[bold red]{get_vibe_status()}[/bold red]")

    console.print(table)

    if not is_vibe_available():
        console.print("\n[yellow]To enable vibe generation:[/yellow]")
        if not has_anthropic:
            console.print("  pip install anthropic")
        if not api_key:
            console.print("  export ANTHROPIC_API_KEY=your-api-key")


@main.command()
@click.argument('input_path', type=click.Path(exists=True))
@click.option('--threshold', '-t', default=0.1, type=float,
              help='Minimum confidence threshold (0.0-1.0)')
@click.option('--raw', '-R', is_flag=True,
              help='Show raw detection scores')
def detect(input_path, threshold, raw):
    """Detect instruments, genres, and sounds in an audio file using PANNs.

    This uses a neural network trained on AudioSet to identify:
    - Instruments (piano, guitar, synthesizer, strings, etc.)
    - Drums (drum machine, hi-hat, snare, etc.)
    - Vocals (male/female singing)
    - Genres (house, techno, disco, funk, etc.)
    - Mood (happy, sad, exciting, etc.)

    Examples:
        cratebot detect track.mp3
        cratebot detect track.mp3 --threshold 0.05
        cratebot detect track.mp3 --raw
    """
    from .panns_analyzer import PANNsAnalyzer, is_panns_available, get_panns_status

    if not is_panns_available():
        console.print(f"[bold red]PANNs not available:[/bold red] {get_panns_status()}")
        console.print("\nTo enable sound detection:")
        console.print("  pip install panns-inference torch librosa")
        return

    console.print(f"[bold green]Detecting sounds in:[/bold green] {input_path}")
    console.print(f"Threshold: {threshold}")

    try:
        analyzer = PANNsAnalyzer()
        detections = analyzer.detect_sounds(input_path, threshold=threshold)

        if raw:
            # Show raw detections with scores
            table = Table(title="Raw Detections")
            table.add_column("Score", style="cyan", width=8)
            table.add_column("Label", style="green")

            for label, score in detections['all_detections'][:25]:
                score_str = f"{score:.2f}"
                if score >= 0.3:
                    table.add_row(f"[bold]{score_str}[/bold]", f"[bold]{label}[/bold]")
                elif score >= 0.15:
                    table.add_row(score_str, label)
                else:
                    table.add_row(f"[dim]{score_str}[/dim]", f"[dim]{label}[/dim]")

            console.print(table)

        else:
            # Show categorized detections
            console.print()

            # Instruments
            if detections['instruments']:
                console.print("[bold cyan]Instruments:[/bold cyan]")
                for label, score in detections['instruments'][:5]:
                    console.print(f"  • {label} ({score:.0%})")

            # Drums
            if detections['drums']:
                console.print("[bold cyan]Drums:[/bold cyan]")
                for label, score in detections['drums'][:4]:
                    console.print(f"  • {label} ({score:.0%})")

            # Vocals
            if detections['vocals']:
                console.print("[bold cyan]Vocals:[/bold cyan]")
                for label, score in detections['vocals'][:3]:
                    console.print(f"  • {label} ({score:.0%})")

            # Genres
            if detections['genres']:
                console.print("[bold cyan]Genres/Style:[/bold cyan]")
                for label, score in detections['genres'][:4]:
                    console.print(f"  • {label} ({score:.0%})")

            # Mood
            if detections['mood']:
                console.print("[bold cyan]Mood:[/bold cyan]")
                for label, score in detections['mood'][:3]:
                    console.print(f"  • {label} ({score:.0%})")

        # Always show formatted summary
        console.print()
        console.print("[bold]Summary:[/bold]")
        console.print(f"  {analyzer.format_detections(detections, min_score=threshold)}")

    except Exception as e:
        console.print(f"[bold red]Error:[/bold red] {str(e)}")
        import traceback
        traceback.print_exc()


@main.command()
def download_clap():
    """Download CLAP model for semantic audio embeddings (~600MB)."""
    from .clap_analyzer import CLAPAnalyzer, is_clap_available, get_clap_status

    console.print("[bold green]CLAP Model Download[/bold green]")
    console.print()

    # Check current status
    status = get_clap_status()
    if status == "Available":
        console.print("[green]CLAP model is already downloaded and ready.[/green]")
        return

    console.print(f"Current status: {status}")
    console.print()

    # Download
    console.print("Downloading CLAP model (630k-audioset-best.pt)...")
    console.print("This may take a few minutes (~600MB).")
    console.print()

    analyzer = CLAPAnalyzer(auto_load=False)

    def progress_callback(progress: float):
        console.print(f"\r  Progress: {progress*100:.1f}%", end="")

    try:
        success = analyzer.download_model(progress_callback)
        console.print()

        if success:
            console.print("[bold green]Download complete![/bold green]")
            console.print("CLAP model is now ready for use.")
        else:
            console.print("[bold red]Download failed.[/bold red]")
            console.print("Check your internet connection and try again.")

    except Exception as e:
        console.print(f"\n[bold red]Error:[/bold red] {str(e)}")


@main.command()
def train_jamendo():
    """Train Jamendo mood/theme classifiers (~5-10 minutes)."""
    from .jamendo_trainer import train_jamendo_classifiers
    from .jamendo_classifier import is_jamendo_available, get_jamendo_status

    console.print("[bold green]Jamendo Classifier Training[/bold green]")
    console.print()

    # Check current status
    if is_jamendo_available():
        console.print("[green]Jamendo classifiers are already trained and ready.[/green]")
        console.print()
        console.print("To retrain, delete: ~/.cratebot/jamendo_models/")
        return

    console.print("Training 56 mood/theme classifiers on CLAP embeddings...")
    console.print("This will take approximately 5-10 minutes.")
    console.print()

    def progress_callback(stage: str, progress: float):
        console.print(f"  {stage}: {progress*100:.0f}%")

    try:
        success = train_jamendo_classifiers(progress_callback)

        if success:
            console.print()
            console.print("[bold green]Training complete![/bold green]")
            console.print("Jamendo classifiers are now ready for use.")
        else:
            console.print()
            console.print("[bold red]Training failed.[/bold red]")

    except Exception as e:
        console.print(f"\n[bold red]Error:[/bold red] {str(e)}")
        import traceback
        traceback.print_exc()


@main.command()
def model_status():
    """Check status of all optional ML models."""
    from .essentia_analyzer import is_essentia_available, get_essentia_status
    from .panns_analyzer import is_panns_available, get_panns_status
    from .clap_analyzer import is_clap_available, get_clap_status
    from .jamendo_classifier import is_jamendo_available, get_jamendo_status

    console.print("[bold green]ML Model Status[/bold green]")
    console.print()

    table = Table()
    table.add_column("Model", style="cyan")
    table.add_column("Status", style="white")
    table.add_column("Features", style="dim")

    # Essentia
    if is_essentia_available():
        table.add_row("Essentia", "[green]Available[/green]", "8 dims (mood, danceability, vocals)")
    else:
        table.add_row("Essentia", f"[red]{get_essentia_status()}[/red]", "8 dims (mood, danceability, vocals)")

    # PANNs
    if is_panns_available():
        table.add_row("PANNs", "[green]Available[/green]", "32 dims (genre, instruments, drums)")
    else:
        table.add_row("PANNs", f"[red]{get_panns_status()}[/red]", "32 dims (genre, instruments, drums)")

    # CLAP
    if is_clap_available():
        table.add_row("CLAP", "[green]Available[/green]", "32 dims (semantic audio understanding)")
    else:
        table.add_row("CLAP", f"[yellow]{get_clap_status()}[/yellow]", "32 dims (semantic audio understanding)")

    # Jamendo
    if is_jamendo_available():
        table.add_row("Jamendo", "[green]Available[/green]", "56 dims (mood/theme predictions)")
    else:
        table.add_row("Jamendo", f"[yellow]{get_jamendo_status()}[/yellow]", "56 dims (mood/theme predictions)")

    console.print(table)

    # Summary
    console.print()
    total_dims = 57  # Base librosa features
    if is_essentia_available():
        total_dims += 8
    if is_panns_available():
        total_dims += 32
    if is_clap_available():
        total_dims += 32
    if is_jamendo_available():
        total_dims += 56

    console.print(f"Total feature vector size: [bold]{total_dims}[/bold] dimensions")

    # Installation hints
    if not is_clap_available() or not is_jamendo_available():
        console.print()
        console.print("[dim]To enable all features:[/dim]")
        if not is_clap_available():
            console.print("  cratebot download-clap")
        if not is_jamendo_available():
            console.print("  cratebot train-jamendo")


if __name__ == "__main__":
    main()
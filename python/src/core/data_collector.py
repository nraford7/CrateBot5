import os
import sys
import pickle
import json
from typing import Dict, List, Any, Tuple
from pathlib import Path
import pandas as pd
from tqdm import tqdm

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from core.audio_analyzer import AudioAnalyzer
from core.tag_manager import TagManager


class DataCollector:
    def __init__(self, analyzer: AudioAnalyzer = None, tag_manager: TagManager = None):
        self.analyzer = analyzer or AudioAnalyzer()
        self.tag_manager = tag_manager or TagManager()
        self.collected_data = []
    
    def collect_from_directory(self, directory_path: str, 
                             recursive: bool = True,
                             save_intermediate: bool = True,
                             output_dir: str = "data/training") -> Tuple[List[Dict], Dict]:
        mp3_files = self._find_mp3_files(directory_path, recursive)
        
        if not mp3_files:
            raise ValueError(f"No MP3 files found in {directory_path}")
        
        print(f"Found {len(mp3_files)} MP3 files to process")
        
        successful = 0
        failed = 0
        
        for mp3_path in tqdm(mp3_files, desc="Processing MP3 files"):
            try:
                tags = self.tag_manager.read_tags(mp3_path)
                
                if not tags or 'all_text' not in tags or not tags['all_text'].strip():
                    print(f"Skipping {os.path.basename(mp3_path)} - no tags found")
                    continue
                
                features = self.analyzer.extract_features(mp3_path)
                
                data_point = {
                    'file_path': mp3_path,
                    'file_name': os.path.basename(mp3_path),
                    'features': features,
                    'tags': tags,
                    'feature_vector': features['feature_vector'],
                    'tag_text': tags['all_text']
                }
                
                self.collected_data.append(data_point)
                successful += 1
                
                if save_intermediate and successful % 10 == 0:
                    self._save_checkpoint(output_dir, successful)
                    
            except Exception as e:
                print(f"Error processing {mp3_path}: {str(e)}")
                failed += 1
                continue
        
        print(f"\nProcessing complete: {successful} successful, {failed} failed")
        
        vocabulary = self._extract_vocabulary()
        
        if save_intermediate:
            self._save_final_dataset(output_dir, vocabulary)
        
        return self.collected_data, vocabulary
    
    def _find_mp3_files(self, directory_path: str, recursive: bool) -> List[str]:
        mp3_files = []
        path = Path(directory_path)
        
        if recursive:
            pattern = '**/*.mp3'
        else:
            pattern = '*.mp3'
        
        for file_path in path.glob(pattern):
            mp3_files.append(str(file_path))
        
        return sorted(mp3_files)
    
    def _extract_vocabulary(self) -> Dict[str, Any]:
        all_tags = [item['tags'] for item in self.collected_data]
        vocabulary = self.tag_manager.extract_vocabulary(all_tags)
        
        vocabulary['total_samples'] = len(self.collected_data)
        vocabulary['unique_patterns'] = len(set(vocabulary['tag_patterns']))
        
        return vocabulary
    
    def _save_checkpoint(self, output_dir: str, count: int) -> None:
        os.makedirs(output_dir, exist_ok=True)
        checkpoint_path = os.path.join(output_dir, f'checkpoint_{count}.pkl')
        
        with open(checkpoint_path, 'wb') as f:
            pickle.dump(self.collected_data, f)
    
    def _save_final_dataset(self, output_dir: str, vocabulary: Dict) -> None:
        os.makedirs(output_dir, exist_ok=True)
        
        with open(os.path.join(output_dir, 'training_data.pkl'), 'wb') as f:
            pickle.dump(self.collected_data, f)
        
        with open(os.path.join(output_dir, 'vocabulary.json'), 'w') as f:
            vocab_serializable = vocabulary.copy()
            vocab_serializable['custom_descriptors'] = {
                k: list(set(v)) for k, v in vocabulary['custom_descriptors'].items()
            }
            json.dump(vocab_serializable, f, indent=2)
        
        df = pd.DataFrame([
            {
                'file_name': item['file_name'],
                'tag_text': item['tag_text'],
                'tempo': item['features']['tempo'],
                'spectral_centroid': item['features']['spectral_centroid'],
                'has_fingerprint': item['features']['fingerprint'] is not None
            }
            for item in self.collected_data
        ])
        df.to_csv(os.path.join(output_dir, 'training_summary.csv'), index=False)
        
        print(f"Dataset saved to {output_dir}/")
        print(f"  - training_data.pkl: Full dataset with features and tags")
        print(f"  - vocabulary.json: Extracted vocabulary and patterns")
        print(f"  - training_summary.csv: Summary statistics")
    
    def load_dataset(self, dataset_path: str) -> List[Dict]:
        with open(dataset_path, 'rb') as f:
            self.collected_data = pickle.load(f)
        return self.collected_data
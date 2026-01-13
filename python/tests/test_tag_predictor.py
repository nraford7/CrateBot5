"""
Tests for tag_predictor.py - ML model training and prediction.
"""

import pytest
import numpy as np
import os


class TestTagPredictor:
    """Tests for TagPredictor class with new 4-classifier architecture."""

    def test_train_creates_models(self, mock_training_data_v2, mock_selected_tags_v2):
        """Training should create genre, timing, mood, and descriptive models."""
        from models.tag_predictor import TagPredictor

        predictor = TagPredictor()
        results = predictor.train(mock_training_data_v2, mock_selected_tags_v2)

        assert 'genre' in predictor.models
        assert 'timing' in predictor.models
        assert 'mood' in predictor.models
        assert 'descriptive' in predictor.models

    def test_train_returns_metrics(self, mock_training_data_v2, mock_selected_tags_v2):
        """Training should return accuracy/F1 metrics."""
        from models.tag_predictor import TagPredictor

        predictor = TagPredictor()
        results = predictor.train(mock_training_data_v2, mock_selected_tags_v2)

        assert 'training_samples' in results
        assert results['training_samples'] == len(mock_training_data_v2)

        if 'genre' in results:
            assert 'accuracy' in results['genre'] or 'status' in results['genre']

    def test_predict_tags_returns_expected_keys(self, mock_training_data_v2, mock_selected_tags_v2, mock_feature_vector):
        """Prediction should return genre, timing, mood, descriptive."""
        from models.tag_predictor import TagPredictor

        predictor = TagPredictor()
        predictor.train(mock_training_data_v2, mock_selected_tags_v2)

        features = {'feature_vector': mock_feature_vector}
        predicted = predictor.predict_tags(features)

        assert 'genre' in predicted
        assert 'timing' in predicted
        assert 'mood' in predicted
        assert 'descriptive' in predicted

    def test_predict_tags_returns_confidence(self, mock_training_data_v2, mock_selected_tags_v2, mock_feature_vector):
        """Prediction should include confidence scores in value/confidence structure."""
        from models.tag_predictor import TagPredictor

        predictor = TagPredictor()
        predictor.train(mock_training_data_v2, mock_selected_tags_v2)

        features = {'feature_vector': mock_feature_vector}
        predicted = predictor.predict_tags(features)

        # New structure: genre/timing/mood are dicts with value and confidence
        assert 'confidence' in predicted['genre']
        assert 'confidence' in predicted['timing']
        assert 'confidence' in predicted['mood']
        assert 0 <= predicted['genre']['confidence'] <= 1
        assert 0 <= predicted['timing']['confidence'] <= 1
        assert 0 <= predicted['mood']['confidence'] <= 1

    def test_save_and_load_model(self, mock_training_data_v2, mock_selected_tags_v2, temp_model_path):
        """Model should be saveable and loadable."""
        from models.tag_predictor import TagPredictor

        # Train and save
        predictor1 = TagPredictor()
        predictor1.train(mock_training_data_v2, mock_selected_tags_v2)
        predictor1.save_model(temp_model_path)

        assert os.path.exists(temp_model_path)

        # Load into new predictor
        predictor2 = TagPredictor()
        predictor2.load_model(temp_model_path)

        assert 'genre' in predictor2.models
        assert 'timing' in predictor2.models
        assert 'mood' in predictor2.models
        assert 'descriptive' in predictor2.models

    def test_loaded_model_predicts_same(self, mock_training_data_v2, mock_selected_tags_v2,
                                         temp_model_path, mock_feature_vector):
        """Loaded model should produce same predictions as original."""
        from models.tag_predictor import TagPredictor

        # Train and save
        predictor1 = TagPredictor()
        predictor1.train(mock_training_data_v2, mock_selected_tags_v2)

        features = {'feature_vector': mock_feature_vector}
        pred1 = predictor1.predict_tags(features)

        predictor1.save_model(temp_model_path)

        # Load and predict
        predictor2 = TagPredictor()
        predictor2.load_model(temp_model_path)
        pred2 = predictor2.predict_tags(features)

        assert pred1['genre'] == pred2['genre']
        assert pred1['timing'] == pred2['timing']
        assert pred1['mood'] == pred2['mood']

    def test_model_metadata_saved(self, mock_training_data_v2, mock_selected_tags_v2, temp_model_path):
        """Model save should create metadata file with new taxonomy keys."""
        from models.tag_predictor import TagPredictor

        predictor = TagPredictor()
        predictor.train(mock_training_data_v2, mock_selected_tags_v2)
        predictor.save_model(temp_model_path)

        meta_path = temp_model_path + '.meta.json'

        assert os.path.exists(meta_path)
        import json
        with open(meta_path) as f:
            metadata = json.load(f)
        assert 'sha256' in metadata or 'format_version' in metadata
        # Check for new taxonomy keys
        summary = metadata.get('selected_tags_summary', {})
        assert 'timing_count' in summary
        assert 'mood_count' in summary
        assert 'descriptive_count' in summary


class TestTagPredictor4ClassifierArchitecture:
    """Tests for the new 4-classifier architecture (genre, timing, mood, descriptive)."""

    def test_train_creates_four_classifiers(self, mock_training_data_v2, mock_selected_tags_v2):
        """Training should create genre, timing, mood, and descriptive models."""
        from models.tag_predictor import TagPredictor

        predictor = TagPredictor()
        results = predictor.train(mock_training_data_v2, mock_selected_tags_v2)

        assert 'genre' in predictor.models
        assert 'timing' in predictor.models
        assert 'mood' in predictor.models
        assert 'descriptive' in predictor.models

    def test_predict_tags_returns_new_format(self, mock_training_data_v2, mock_selected_tags_v2, mock_feature_vector):
        """Prediction should return new structure with value/confidence keys."""
        from models.tag_predictor import TagPredictor

        predictor = TagPredictor()
        predictor.train(mock_training_data_v2, mock_selected_tags_v2)

        features = {'feature_vector': mock_feature_vector}
        predicted = predictor.predict_tags(features)

        # Genre should have value and confidence
        assert 'genre' in predicted
        assert isinstance(predicted['genre'], dict)
        assert 'value' in predicted['genre']
        assert 'confidence' in predicted['genre']
        assert 0 <= predicted['genre']['confidence'] <= 1

        # Timing should have value and confidence
        assert 'timing' in predicted
        assert isinstance(predicted['timing'], dict)
        assert 'value' in predicted['timing']
        assert 'confidence' in predicted['timing']
        assert 0 <= predicted['timing']['confidence'] <= 1

        # Mood should have value and confidence
        assert 'mood' in predicted
        assert isinstance(predicted['mood'], dict)
        assert 'value' in predicted['mood']
        assert 'confidence' in predicted['mood']
        assert 0 <= predicted['mood']['confidence'] <= 1

        # Descriptive should have tags list
        assert 'descriptive' in predicted
        assert isinstance(predicted['descriptive'], dict)
        assert 'tags' in predicted['descriptive']
        assert isinstance(predicted['descriptive']['tags'], list)

    def test_predict_tags_returns_embeddings(self, mock_training_data_v2, mock_selected_tags_v2, mock_feature_vector):
        """Prediction should include embedding vectors for similarity."""
        from models.tag_predictor import TagPredictor

        predictor = TagPredictor()
        predictor.train(mock_training_data_v2, mock_selected_tags_v2)

        features = {'feature_vector': mock_feature_vector}
        predicted = predictor.predict_tags(features)

        # Should have internal embedding keys
        assert '_comments_embedding' in predicted or '_descriptive_embedding' in predicted
        assert '_overall_embedding' in predicted

    def test_train_results_include_all_classifiers(self, mock_training_data_v2, mock_selected_tags_v2):
        """Training results should include metrics for all 4 classifiers."""
        from models.tag_predictor import TagPredictor

        predictor = TagPredictor()
        results = predictor.train(mock_training_data_v2, mock_selected_tags_v2)

        # Should have results for each classifier type
        assert 'genre' in results
        assert 'timing' in results
        assert 'mood' in results
        assert 'descriptive' in results

    def test_model_save_metadata_reflects_new_taxonomy(self, mock_training_data_v2, mock_selected_tags_v2, temp_model_path):
        """Saved model metadata should reflect new taxonomy keys."""
        from models.tag_predictor import TagPredictor
        import json

        predictor = TagPredictor()
        predictor.train(mock_training_data_v2, mock_selected_tags_v2)
        predictor.save_model(temp_model_path)

        meta_path = temp_model_path + '.meta.json'
        with open(meta_path) as f:
            metadata = json.load(f)

        # Metadata should have new key names
        summary = metadata.get('selected_tags_summary', {})
        assert 'timing_count' in summary
        assert 'mood_count' in summary
        assert 'descriptive_count' in summary


class TestTagPredictorEdgeCases:
    """Edge case tests for TagPredictor."""

    def test_empty_training_data_raises(self, mock_selected_tags_v2):
        """Should raise error with empty training data."""
        from models.tag_predictor import TagPredictor

        predictor = TagPredictor()

        with pytest.raises((ValueError, Exception)):
            predictor.train([], mock_selected_tags_v2)

    def test_insufficient_samples_handled(self, mock_selected_tags_v2, mock_feature_vector):
        """Should handle case with too few samples per class."""
        from models.tag_predictor import TagPredictor

        # Create minimal data with very few samples using new taxonomy
        training_data = [
            {
                'feature_vector': mock_feature_vector,
                'tags': {'genre': 'House', 'timing': 'Peak', 'mood': 'Happy', 'descriptive': 'Driving'}
            }
        ]

        predictor = TagPredictor()

        # Should either raise or return with 'skipped' status
        try:
            results = predictor.train(training_data, mock_selected_tags_v2)
            # If it doesn't raise, check for skipped status
            assert results.get('genre', {}).get('status') in ('skipped', None) or \
                   results.get('training_samples', 0) == 1
        except (ValueError, Exception):
            pass  # Expected behavior

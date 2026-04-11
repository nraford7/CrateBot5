#!/usr/bin/env python3
"""
Pre-compute CLAP text embeddings for CrateBot's tag vocabulary.
Uses LAION-CLAP text encoder to generate 512-dim embeddings for each tag.
Output: JSON file with tag -> embedding mapping.
"""
import json, sys, os
import numpy as np

def main():
    try:
        import laion_clap
    except ImportError:
        print("Error: laion-clap is not installed.")
        print("Install it with: pip install laion-clap")
        print("  (requires Python 3.8+ and PyTorch)")
        sys.exit(1)

    # Load CLAP model (text encoder only needed)
    print("Loading CLAP model...")
    model = laion_clap.CLAP_Module(enable_fusion=False)
    model.load_ckpt()

    # DJ tag vocabulary with natural language descriptions
    # Format: tag_name -> description for text encoding
    tag_descriptions = {
        # Genre
        "House": "house music electronic dance four on the floor kick drum",
        "Techno": "techno music electronic industrial repetitive",
        "Acapella": "acapella vocals only no instruments singing",
        # Mood
        "Happy": "happy uplifting joyful positive cheerful music",
        "Aggressive": "aggressive intense hard heavy powerful music",
        "Dark/Intense": "dark intense moody sinister brooding music",
        "Emotional": "emotional moving heartfelt soulful deep music",
        "Floating/Spacey": "ambient spacey floating ethereal dreamy atmospheric music",
        # Timing
        "Build": "building rising tension growing energy crescendo",
        "Release": "release drop peak energy climax",
        "Start": "intro opening beginning start of track",
        "Sustain": "sustained steady maintaining groove constant energy",
        # Rhythm
        "Broken": "broken beat irregular syncopated rhythm",
        "Driving": "driving relentless forward propulsive rhythm",
        "Loopy": "loopy repetitive hypnotic cycling pattern",
        "Swung": "swing swung shuffle groove triplet feel",
        # Vibes
        "Bouncy": "bouncy fun playful upbeat energetic groove",
        "Dope": "cool dope hip stylish smooth groove",
        "Dreamy": "dreamy atmospheric lush ethereal soundscape",
        "Dubby": "dub reggae delay echo spacey bass",
        "Epic": "epic cinematic grand dramatic powerful orchestral",
        "Fun": "fun playful light party celebration",
        "Funky": "funky groove funk bass guitar rhythm",
        "Glitchy": "glitch digital distorted electronic experimental",
        "Grindy": "grindy grinding dirty raw distorted bass",
        "Jazzy": "jazz jazzy saxophone piano improvisation swing",
        "Joyful": "joyful happy uplifting celebration joy",
        "Melodic": "melodic beautiful melody harmonious musical",
        "Techy": "techy technical precise minimal electronic",
        "Tropical": "tropical warm latin caribbean percussion sunny",
        # Style
        "Afro": "african afrobeat percussion tribal rhythmic",
        "Arabic": "arabic middle eastern oriental oud percussion",
        "Classic": "classic timeless old school traditional",
        "Disco": "disco funk dance groove four on the floor bass",
        "Electro": "electro electronic synthesizer robotic digital",
        "Poppy": "pop catchy mainstream hook melody vocal",
        "Spiritual": "spiritual meditative zen peaceful transcendent",
        # Instruments
        "Arpeggiated": "arpeggio synthesizer sequenced repeating notes",
        "Beats": "percussion drums beat rhythm kick snare",
        "Congas": "conga percussion hand drums latin african",
        "Guitar": "guitar acoustic electric string instrument",
        "Hi Hats": "hi hat cymbal percussion metallic rhythmic",
        "Horns": "horn brass trumpet saxophone wind instrument",
        "Organ": "organ keyboard church hammond electric",
        "Pads": "pad synthesizer ambient sustained warm texture",
        "Piano": "piano keyboard acoustic melodic chord",
        "Strings": "strings violin cello orchestra bowed",
        "Sweeps": "sweep riser effect transition filter",
        # Other
        "Dirty": "dirty raw gritty distorted rough unpolished",
        "Head Knodding": "head nodding groove mid tempo bobbing rhythm",
    }

    # Encode all descriptions
    descriptions = list(tag_descriptions.values())
    tags = list(tag_descriptions.keys())

    print(f"Encoding {len(tags)} tag descriptions...")
    text_embeddings = model.get_text_embedding(descriptions, use_tensor=False)

    # Build output dict with normalized embeddings
    output = {}
    for tag, embedding in zip(tags, text_embeddings):
        # Normalize embedding to unit vector for cosine similarity
        norm = np.linalg.norm(embedding)
        normalized = (embedding / norm).tolist() if norm > 0 else embedding.tolist()
        output[tag] = normalized

    # Save to Resources
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    output_path = os.path.join(
        project_root,
        "CrateBotCore", "Sources", "CrateBotCore", "Resources",
        "clap_tag_embeddings.json"
    )

    with open(output_path, 'w') as f:
        json.dump(output, f)

    print(f"Saved {len(output)} embeddings ({len(output[tags[0]])} dims each) to {output_path}")

if __name__ == "__main__":
    main()

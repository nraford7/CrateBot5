# CrateBot Landing Page

**Live URL:** https://nraford7.github.io/CrateBot5/

## Design System: "Shinjuku Vinyl Session"

### Vibe
- **Reference:** Late night DJ booth in a Tokyo listening bar
- **Emotion:** Sophisticated, confident, nostalgic
- **Collision:** Vinyl record sleeves + neural network diagrams
- **Anti-patterns:** Never mistaken for a crypto project, SaaS product, or tech bro product

### Color Palette: "Golden Hour Booth"
| Color | Hex | Usage |
|-------|-----|-------|
| Gold | `#c9a227` | Primary accent, CTAs, highlights |
| Gold Light | `#e8d4a8` | Secondary accent |
| Dark Wood | `#1a1612` | Secondary background |
| Booth Black | `#0d0b09` | Primary background |
| Sepia | `#6b5c4a` | Muted text |
| Cream | `#f5efe6` | Primary text |

### Typography
- **Display:** Playfair Display (serif) - headlines, section titles
- **Body:** Outfit (sans-serif) - body text, descriptions
- **Mono:** JetBrains Mono - tags, code, technical elements

---

## Page Structure

### Hero
- Headline: "Your crates, understood."
- Badge: "Smart Tagging for DJs"
- Spinning vinyl record with neural network overlay
- Floating tag examples (Vibe, Mnemonic, Genre)
- CTAs: Download for macOS, See How It Works

### Section 01: The Problem
**"Your library is bigger than your memory"**

Pain points:
- Tiny screens, big libraries (CDJ displays)
- Context evaporates (forgot to tag that perfect 3am track)
- Playlists don't scale (mood × energy × genre = impossible)

### Section 02: The Solution
**"CrateBot fixes this."**

- Danny Tenaglia "Music Is The Answer" example card with animated waveform
- Vibe examples: "DARK FLUTE MELODY PEAK", "sweating serpent", "music is the answer"
- Visual: Track card with genre tags (Deep House, Soulful, Peak Time, Classic)

### Section 03: How It Works
**"Three steps to smarter crates, powered by five audio analysis engines."**

**Steps:**
1. **Train** - Point CrateBot at your tagged library
2. **Tag** - Batch process new tracks
3. **Refine** - Review predictions, make corrections, retrain

**Five Audio Intelligence Engines:**
> Built on research from Google, Barcelona's Music Technology Group, and LAION-AI—trained on millions of audio samples and 55,000+ tagged tracks.

| Engine | Function |
|--------|----------|
| Librosa | Spectral & temporal analysis |
| Essentia | Mood & danceability |
| PANNs | Instrument & genre detection |
| CLAP | Semantic audio matching |
| Jamendo | Genre & mood classifiers |

**135+ audio features extracted from every track**

**Model Options:**
- Default Model - Works out of the box
- Custom Training - Train on your own library
- Community Models - Coming soon

### Section 04: Features
**"AI does the tagging. You do the jamming."**

> This isn't AI DJing. CrateBot doesn't select tracks, suggest what to play, or make creative decisions for you. It handles the tedious work of track administration so you can focus on what you do best—reading the room, building a vibe, and creating a moment. AI in support of creativity, not the other way around.

**Features:**
- Tags That Stack - Multi-label taxonomy (Genre, Timing, Mood, Descriptive)
- Hook Detection - Finds memorable vocal phrases
- Batch Processing - Tag thousands while you sleep
- Review & Refine - Inline audio playback for verification
- Writes to ID3 Tags - Works in Rekordbox, Traktor, Serato, CDJs
- Set It & Forget It - New tracks tagged automatically

### Final CTA
> *"A little bit of data and a whole lotta love"*

**"Ready to dig smarter?"**

Download CrateBot and let machine learning organize your crates.

### Footer
- "Built with Claude Code. For DJs, by a DJ."
- Inspired by: Bas Curtiz, Marekkon5, OneTagger, Nonomomomo's "Little Data, Whole Lotta Love"

---

## Technical Details

### Animations
- Vinyl record rotation (20s infinite)
- Neural network node connections (dashed lines)
- Floating tags
- Waveform bars pulse symmetrically around center axis
- Scroll-triggered fade-in for cards and sections

### Responsive Breakpoints
| Breakpoint | Changes |
|------------|---------|
| ≤1024px | 2-col features, stacked vibe content, 3-col tech grid |
| ≤768px | 1-col features, 2-col tech grid, stacked vibe examples |
| ≤480px | Compact spacing, smaller headings, tighter cards |

### External Resources
- Google Fonts: Playfair Display, Outfit, JetBrains Mono
- No external CSS frameworks
- No JavaScript dependencies (vanilla JS only)

---

## Acknowledgments

Inspired by the work of:
- [Bas Curtiz](https://github.com/bascurtiz)
- [Marekkon5](https://github.com/Marekkon5)
- [OneTagger](https://onetagger.github.io/)
- [Nonomomomo's "Little Data, Whole Lotta Love"](https://www.reddit.com/r/DJs/comments/c3o2jk/my_ultimate_track_tagging_system_the_little_data/)

---

## Audio Intelligence Sources

- [PANNs: Large-Scale Pretrained Audio Neural Networks](https://arxiv.org/abs/1912.10211)
- [CLAP: Contrastive Language-Audio Pretraining](https://github.com/LAION-AI/CLAP)
- [Essentia: Music Technology Group](https://github.com/MTG/essentia)
- [MTG-Jamendo Dataset](https://mtg.github.io/mtg-jamendo-dataset/)

# CrateBot3 Design System
## "Vinyl Warmth" Theme

A warm, analog-inspired design system for a music tagging application. Think late-night DJ booth, glowing VU meters, vinyl warmth.

---

## Brand Identity

### Concept
CrateBot is about **crate digging** - that warm, tactile experience of flipping through vinyl records. The design should feel:
- **Warm** - Not cold tech blue, but inviting amber/orange
- **Analog** - Subtle textures, depth, organic shapes
- **Professional** - Clean and functional for serious work
- **Musical** - Audio-inspired elements throughout

### Logo
- Vinyl disc icon with gradient (`amber-400` to `amber-600`)
- "Crate" in primary text, "Bot" in brand amber
- Disc spins during processing tasks

---

## Color Palette

### Primary - Warm Amber
The soul of CrateBot. Used for:
- Primary buttons
- Active states
- Progress indicators
- Waveform progress
- Key highlights

```
amber-400: #fbbf24  (lighter)
amber-500: #f59e0b  (primary)
amber-600: #d97706  (darker/hover)
```

### Secondary - Electric Purple
Creative energy accent. Used sparingly for:
- Special features
- AI-powered elements
- Alerts/notifications

```
violet-500: #8b5cf6
violet-600: #7c3aed
```

### Semantic Colors
```
success: #10b981 (emerald-500)
warning: #f59e0b (amber-500)
danger:  #ef4444 (red-500)
info:    #3b82f6 (blue-500)
```

### Neutrals - Warm Stone
All grays have subtle brown/warm undertones.

**Light Mode:**
```
surface-primary:  #faf9f7  (warm off-white)
surface-elevated: #ffffff  (pure white)
surface-sunken:   #f5f3f0  (warm light gray)
sidebar:          #f0eeeb  (distinct sidebar)

text-primary:     #1c1917  (warm near-black)
text-secondary:   #57534e  (warm gray)
text-muted:       #a8a29e  (stone)

border:           #e7e5e4  (subtle border)
```

**Dark Mode:**
```
surface-primary:  #1a1918  (warm near-black)
surface-elevated: #242322  (elevated dark)
surface-sunken:   #121110  (deepest dark)
sidebar:          #141312  (sidebar dark)

text-primary:     #fafaf9  (off-white)
text-secondary:   #d6d3d1  (light gray)
text-muted:       #78716c  (dim gray)

border:           #3f3f3f  (subtle border)
```

---

## Typography

### Font Stack

**Display (Satoshi)**
- Headers, titles, logo
- Bold, modern, geometric
- Weight: 600-700

**Body (General Sans)**
- All body text, UI elements
- Warm, readable, contemporary
- Weight: 400-600

**Mono (JetBrains Mono)**
- Time displays, counts, technical info
- Clean, tabular numbers
- Weight: 400-500

### Scale

| Name        | Size    | Line Height | Weight | Use Case              |
|-------------|---------|-------------|--------|-----------------------|
| display-lg  | 2.5rem  | 1.1         | 700    | Hero headers          |
| display-md  | 2rem    | 1.15        | 700    | Page titles           |
| display-sm  | 1.5rem  | 1.2         | 600    | Section headers       |
| heading-lg  | 1.25rem | 1.3         | 600    | Card titles           |
| heading-md  | 1.125rem| 1.4         | 600    | Subsection titles     |
| heading-sm  | 1rem    | 1.4         | 600    | Small headings        |
| body-lg     | 1rem    | 1.5         | 400    | Large body text       |
| body-md     | 0.875rem| 1.5         | 400    | Default body          |
| body-sm     | 0.8125rem| 1.5        | 400    | Small body            |
| caption     | 0.75rem | 1.4         | 400    | Labels, metadata      |
| overline    | 0.6875rem| 1.3        | 600    | Category labels       |

---

## Spacing

Base unit: 4px

| Token | Value  |
|-------|--------|
| 1     | 4px    |
| 2     | 8px    |
| 3     | 12px   |
| 4     | 16px   |
| 5     | 20px   |
| 6     | 24px   |
| 8     | 32px   |
| 10    | 40px   |
| 12    | 48px   |

**Common patterns:**
- Card padding: 20px (`p-5`)
- Page padding: 32px (`p-8`)
- Gap between cards: 24px (`gap-6`)
- Button padding: 10px 16px (`py-2.5 px-4`)

---

## Border Radius

| Token | Value  | Use Case                    |
|-------|--------|-----------------------------|
| sm    | 6px    | Badges, small elements      |
| DEFAULT | 8px  | Buttons, inputs             |
| md    | 10px   | Tags, chips                 |
| lg    | 12px   | Cards (inner elements)      |
| xl    | 16px   | Cards, modals               |
| 2xl   | 20px   | Large cards, hero sections  |
| full  | 9999px | Circular elements           |

---

## Shadows

### Elevation Scale
```css
/* Subtle - form inputs, minor separation */
shadow-sm: 0 1px 2px rgba(28, 25, 23, 0.05);

/* Default - buttons, minor UI elements */
shadow: 0 2px 4px rgba(28, 25, 23, 0.06),
        0 1px 2px rgba(28, 25, 23, 0.04);

/* Medium - cards at rest */
shadow-md: 0 4px 8px rgba(28, 25, 23, 0.08),
           0 2px 4px rgba(28, 25, 23, 0.04);

/* Large - cards on hover, dropdowns */
shadow-lg: 0 8px 16px rgba(28, 25, 23, 0.1),
           0 4px 8px rgba(28, 25, 23, 0.05);

/* XL - modals, popovers */
shadow-xl: 0 16px 32px rgba(28, 25, 23, 0.12),
           0 8px 16px rgba(28, 25, 23, 0.06);
```

### Glow Effects (Brand)
```css
/* Amber glow - active states, buttons */
shadow-glow-amber: 0 0 20px rgba(245, 158, 11, 0.3);
shadow-glow-amber-lg: 0 0 40px rgba(245, 158, 11, 0.4);

/* Purple glow - special features */
shadow-glow-violet: 0 0 20px rgba(139, 92, 246, 0.3);
```

---

## Animation

### Timing Functions
```css
--ease-smooth: cubic-bezier(0.4, 0, 0.2, 1);  /* Most transitions */
--ease-bounce: cubic-bezier(0.68, -0.55, 0.265, 1.55);  /* Playful */
--ease-snap: cubic-bezier(0, 0, 0.2, 1);  /* Quick snappy */
```

### Durations
```
Fast: 150ms     - Micro-interactions (hover)
Default: 200ms  - Standard transitions
Medium: 300ms   - Entrance animations
Slow: 400ms     - Complex transitions
```

### Entrance Animations
```css
/* Fade in */
@keyframes fadeIn {
  from { opacity: 0; }
  to { opacity: 1; }
}

/* Slide up (cards, content) */
@keyframes slideUp {
  from { opacity: 0; transform: translateY(10px); }
  to { opacity: 1; transform: translateY(0); }
}

/* Scale in (modals, popovers) */
@keyframes scaleIn {
  from { opacity: 0; transform: scale(0.95); }
  to { opacity: 1; transform: scale(1); }
}
```

### Staggered Animation
Use `animation-delay` for children:
```css
.card:nth-child(1) { animation-delay: 0ms; }
.card:nth-child(2) { animation-delay: 75ms; }
.card:nth-child(3) { animation-delay: 150ms; }
/* etc. */
```

---

## Components

### Buttons

**Primary** (amber gradient)
- Background: `amber-500` → `amber-600` on hover
- Shadow: `shadow-md` + amber glow on hover
- Scale: `0.98` on active

**Secondary** (neutral bordered)
- Background: `surface-sunken`
- Border: `border-light` → `amber-300` on hover
- No shadow → `shadow-sm` on hover

**Ghost** (transparent)
- Background: transparent → `surface-sunken` on hover
- No border, no shadow

### Cards

**Default Card**
- Background: `surface-elevated`
- Padding: 20px
- Border radius: 16px
- Shadow: `shadow-card`

**Interactive Card**
- Hover: lift (`-translate-y-0.5`) + `shadow-card-hover`
- Cursor: pointer

### Inputs

- Background: `surface-sunken`
- Border: 1px `border-light`
- Focus: 2px ring `amber-500/30` + `amber-500` border
- Padding: 10px 14px
- Border radius: 8px

### Progress Bars

- Track: `surface-sunken`, 8px height
- Bar: gradient `amber-500` → `amber-400`
- Add shimmer animation during processing

### Status Indicators

- Dot: 8px circle
- Connected: `emerald-500` + glow
- Connecting: `amber-500` + pulse
- Disconnected: `red-500`

---

## Key Patterns

### Page Structure
```jsx
<motion.div
  variants={containerVariants}
  initial="hidden"
  animate="visible"
  className="p-8 max-w-4xl"
>
  <PageHeader title="..." description="..." />
  <Card className="mb-6">...</Card>
  <Card className="mb-6">...</Card>
  <ActionButtons />
</motion.div>
```

### Card Header with Icon
```jsx
<div className="flex items-center gap-2.5 mb-4">
  <div className="w-8 h-8 rounded-lg bg-amber-100 flex items-center justify-center">
    <Icon className="w-4 h-4 text-amber-600" />
  </div>
  <h2 className="font-display font-semibold text-heading-md">
    Title
  </h2>
</div>
```

### Noise Texture
Add `noise-overlay` class to surfaces for subtle texture:
```css
.noise-overlay::before {
  content: '';
  position: absolute;
  inset: 0;
  background-image: url("data:image/svg+xml,...");
  opacity: 0.03;
  pointer-events: none;
}
```

---

## Implementation Notes

1. **Install fonts** - Add Satoshi and General Sans from Fontshare (free)
2. **Add Framer Motion** - For entrance/layout animations
3. **Update Tailwind config** - Replace current with new design tokens
4. **Apply CSS** - Add custom component styles
5. **Update components** - One at a time, starting with Sidebar and AudioPlayer

---

## File Structure

```
design-mockup/
├── tailwind.config.mockup.js    # Design tokens
├── styles/
│   └── index.mockup.css         # Custom styles
├── components/
│   ├── Sidebar.mockup.tsx       # Redesigned sidebar
│   ├── AudioPlayer.mockup.tsx   # Hero component
│   ├── StatusBar.mockup.tsx     # Simplified status
│   └── TagTab.mockup.tsx        # Full page example
└── DESIGN-SYSTEM.md             # This file
```

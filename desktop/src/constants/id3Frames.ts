/**
 * Shared ID3 Frame Constants
 * Single source of truth for ID3 frame definitions used across the application.
 */

export interface ID3Frame {
  code: string
  name: string
  description: string
  group: string
}

/**
 * Comprehensive list of ID3v2.3/2.4 frames supported by iTunes/Apple Music.
 * Organized by category for easier selection.
 */
export const ID3_FRAMES: ID3Frame[] = [
  // Primary Tags (most commonly used)
  { code: 'TCON', name: 'Genre', description: 'Content type / Genre', group: 'Primary' },
  { code: 'TALB', name: 'Album', description: 'Album/Movie/Show title', group: 'Primary' },
  { code: 'TIT1', name: 'Content Group', description: 'Content group description (Grouping in iTunes)', group: 'Primary' },
  { code: 'TIT2', name: 'Title', description: 'Title/Song name', group: 'Primary' },
  { code: 'TIT3', name: 'Subtitle', description: 'Subtitle/Description refinement', group: 'Primary' },
  { code: 'COMM', name: 'Comments', description: 'Comments field (multi-value)', group: 'Primary' },
  { code: 'TDSC', name: 'Description', description: 'iTunes Description field', group: 'Primary' },

  // Artist Tags
  { code: 'TPE1', name: 'Artist', description: 'Lead performer/Soloist', group: 'Artist' },
  { code: 'TPE2', name: 'Album Artist', description: 'Band/Orchestra/Accompaniment', group: 'Artist' },
  { code: 'TPE3', name: 'Conductor', description: 'Conductor/Performer refinement', group: 'Artist' },
  { code: 'TPE4', name: 'Remixer', description: 'Interpreted, remixed, or modified by', group: 'Artist' },
  { code: 'TCOM', name: 'Composer', description: 'Composer name', group: 'Artist' },
  { code: 'TEXT', name: 'Lyricist', description: 'Lyricist/Text writer', group: 'Artist' },

  // Sorting Tags (iTunes specific)
  { code: 'TSOT', name: 'Sort Title', description: 'Title sort order', group: 'Sorting' },
  { code: 'TSOA', name: 'Sort Album', description: 'Album sort order', group: 'Sorting' },
  { code: 'TSOP', name: 'Sort Artist', description: 'Performer sort order', group: 'Sorting' },
  { code: 'TSO2', name: 'Sort Album Artist', description: 'Album artist sort order', group: 'Sorting' },
  { code: 'TSOC', name: 'Sort Composer', description: 'Composer sort order', group: 'Sorting' },

  // Classification Tags
  { code: 'TCAT', name: 'Category', description: 'Category (podcast category in iTunes)', group: 'Classification' },
  { code: 'GRP1', name: 'Grouping', description: 'Grouping (iTunes grouping field)', group: 'Classification' },
  { code: 'MVNM', name: 'Movement Name', description: 'Movement name (classical)', group: 'Classification' },
  { code: 'MVIN', name: 'Movement Number', description: 'Movement number/count', group: 'Classification' },
  { code: 'TKEY', name: 'Key', description: 'Initial key (musical)', group: 'Classification' },
  { code: 'TBPM', name: 'Beats Per Minute', description: 'BPM tempo value', group: 'Classification' },
  { code: 'TLAN', name: 'Language', description: 'Language(s) of text/lyrics', group: 'Classification' },
  { code: 'TMOO', name: 'Mood', description: 'Mood (ID3v2.4)', group: 'Classification' },
  { code: 'TFLT', name: 'Kind', description: 'File type / Audio type', group: 'Classification' },
  { code: 'TMED', name: 'Media Type', description: 'Media type (CD, Vinyl, etc.)', group: 'Classification' },

  // Rating & Play Stats (iTunes)
  { code: 'POPM', name: 'Rating', description: 'Popularimeter / Star rating', group: 'Stats' },
  { code: 'PCNT', name: 'Plays', description: 'Play counter', group: 'Stats' },
  { code: 'TXXX:RATING', name: 'Rating (Text)', description: 'Text-based rating value', group: 'Stats' },
  { code: 'TXXX:PLAY_COUNT', name: 'Play Count', description: 'Number of plays', group: 'Stats' },
  { code: 'TXXX:SKIP_COUNT', name: 'Skips', description: 'Number of skips', group: 'Stats' },
  { code: 'TXXX:LAST_PLAYED', name: 'Last Played', description: 'Last played timestamp', group: 'Stats' },
  { code: 'TXXX:LAST_SKIPPED', name: 'Last Skipped', description: 'Last skipped timestamp', group: 'Stats' },

  // Publishing Tags
  { code: 'TPUB', name: 'Publisher', description: 'Publisher/Label', group: 'Publishing' },
  { code: 'TCOP', name: 'Copyright', description: 'Copyright message', group: 'Publishing' },
  { code: 'TENC', name: 'Encoded By', description: 'Encoded by', group: 'Publishing' },
  { code: 'TOWN', name: 'Owner', description: 'File owner/licensee', group: 'Publishing' },
  { code: 'WCOP', name: 'Copyright URL', description: 'Copyright/Legal URL', group: 'Publishing' },
  { code: 'WPUB', name: 'Publisher URL', description: 'Publisher official URL', group: 'Publishing' },

  // Date/Time Tags
  { code: 'TDRC', name: 'Recording Date', description: 'Recording time (ID3v2.4)', group: 'Date' },
  { code: 'TDRL', name: 'Release Date', description: 'Release time (ID3v2.4)', group: 'Date' },
  { code: 'TYER', name: 'Year', description: 'Year of recording (ID3v2.3)', group: 'Date' },
  { code: 'TDAT', name: 'Date', description: 'Date (DDMM format, ID3v2.3)', group: 'Date' },
  { code: 'TDEN', name: 'Date Added', description: 'Encoding time / Date added', group: 'Date' },
  { code: 'TDTG', name: 'Date Modified', description: 'Tagging time / Date modified', group: 'Date' },
  { code: 'TXXX:PURCHASE_DATE', name: 'Purchase Date', description: 'iTunes purchase date', group: 'Date' },

  // Track/Disc Tags
  { code: 'TRCK', name: 'Track Number', description: 'Track number/Position in set', group: 'Track' },
  { code: 'TPOS', name: 'Disc Number', description: 'Part of a set (disc number)', group: 'Track' },
  { code: 'TLEN', name: 'Length', description: 'Length in milliseconds', group: 'Track' },
  { code: 'TSIZ', name: 'Size', description: 'Size in bytes', group: 'Track' },
  { code: 'TXXX:SAMPLE_RATE', name: 'Sample Rate', description: 'Audio sample rate', group: 'Track' },

  // Album Metadata
  { code: 'TXXX:ALBUM_RATING', name: 'Album Rating', description: 'Album-level rating', group: 'Album' },
  { code: 'TXXX:FAVORITE', name: 'Favorite', description: 'Favorite/loved status', group: 'Album' },
  { code: 'TXXX:EQUALIZER', name: 'Equalizer', description: 'Equalizer preset name', group: 'Album' },

  // Cloud/Sync Tags (iTunes specific)
  { code: 'TXXX:CLOUD_STATUS', name: 'Cloud Status', description: 'iCloud sync status', group: 'Cloud' },
  { code: 'TXXX:CLOUD_DOWNLOAD', name: 'Cloud Download', description: 'iCloud download status', group: 'Cloud' },

  // Custom CrateBot Tags
  { code: 'TXXX:CRATEBOT_TIMING', name: 'CrateBot Timing', description: 'Custom timing tag (CrateBot)', group: 'Custom' },
  { code: 'TXXX:CRATEBOT_MOOD', name: 'CrateBot Mood', description: 'Custom mood tag (CrateBot)', group: 'Custom' },
  { code: 'TXXX:CRATEBOT_GENRE', name: 'CrateBot Genre', description: 'Custom genre tag (CrateBot)', group: 'Custom' },
  { code: 'TXXX:CRATEBOT_DESCRIPTIVE', name: 'CrateBot Descriptive', description: 'Custom descriptive tag (CrateBot)', group: 'Custom' },
  { code: 'TXXX:CRATEBOT_VIBE_SHORT', name: 'CrateBot Vibe (Short)', description: 'Short AI vibe description', group: 'Custom' },
  { code: 'TXXX:CRATEBOT_VIBE_LONG', name: 'CrateBot Vibe (Long)', description: 'Long AI vibe description', group: 'Custom' },
  { code: 'TXXX:CRATEBOT_HOOK', name: 'CrateBot Hook', description: 'Detected hook timestamp', group: 'Custom' },
  { code: 'TXXX:ENERGY', name: 'Energy', description: 'Energy level (DJ software)', group: 'Custom' },
]

/**
 * Group names for organizing frames in the UI.
 * Order determines display order in dropdowns.
 */
export const FRAME_GROUPS = [
  'Primary',
  'Classification',
  'Artist',
  'Sorting',
  'Stats',
  'Album',
  'Publishing',
  'Date',
  'Track',
  'Cloud',
  'Custom',
] as const

/**
 * Frame codes suitable for tagging target dropdowns.
 * Subset of frames commonly used for tag assignment.
 */
const TAGGING_TARGET_FRAME_CODES = [
  'TCON',
  'TALB',
  'TIT1',
  'TIT3',
  'COMM',
  'TDSC',
  'GRP1',
  'TMOO',
  'TXXX:CRATEBOT_GENRE',
  'TXXX:CRATEBOT_TIMING',
  'TXXX:CRATEBOT_MOOD',
  'TXXX:CRATEBOT_DESCRIPTIVE',
  'TXXX:CRATEBOT_VIBE_SHORT',
  'TXXX:CRATEBOT_VIBE_LONG',
  'TXXX:CRATEBOT_HOOK',
]

/**
 * Filtered subset of frames for tagging target dropdowns.
 */
export const TAGGING_TARGET_FRAMES: ID3Frame[] = ID3_FRAMES.filter(
  (frame) => TAGGING_TARGET_FRAME_CODES.includes(frame.code)
).concat([
  // Add CRATEBOT_HOOK which isn't in the main list but is used for hooks
  { code: 'TXXX:CRATEBOT_HOOK', name: 'CrateBot Hook', description: 'Detected hook timestamp', group: 'Custom' },
])

/**
 * Returns frame options in { value, label } format for select dropdowns.
 */
export function getFrameOptions(): Array<{ value: string; label: string }> {
  return TAGGING_TARGET_FRAMES.map((frame) => ({
    value: frame.code,
    label: frame.name ? `${frame.code} (${frame.name})` : frame.code,
  }))
}

/**
 * Returns all frame options for source selection (full iTunes-compatible list).
 */
export function getAllFrameOptions(): Array<{ value: string; label: string }> {
  return ID3_FRAMES.map((frame) => ({
    value: frame.code,
    label: frame.name ? `${frame.code} (${frame.name})` : frame.code,
  }))
}

<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Design

Design, requirements, and direction. The active pre-v1.0.0 bug/feature task list lives in `backlog.md`.

## Assumptions

- Cross-platform CLI file renaming+moving|copying utility. Written in Go, single static binary.

- Has one goal as a project: rename + copy/move regular files and media (e.g. SD card -> array), more safety and robustly than anything else available.

## Scope

- In scope: derive a canonical date/time (+ counter) per file, rename, copy or move, dedupe; stash original metadata in file xattrs.

- Out of scope: GUI, configuration UI, remembered state beyond the layered config file, editing/converting media.

## Requirements

### CLI

- Syntax: `rpdc [flags] <source/> <dest/>`  (binary name TBD - see Gotchas).

- Copies by default. Copy uses the kernel `cp --reflink=auto` equivalent (if available on platform and filesystem), quietly.

- Most flags below should also be settable as a user config file setting (see Configuration).

#### Flags

##### Date/counter sourcing

- `--no-mtime`: never use mtime for date/time, even as last resort (mtime isn't always trustworthy).
- `--no-filename-date`: don't try to derive date/time from the filename.
- `--no-filename-counter`: don't try to derive a counter from the filename.

##### Time adjustment

- `--adjust-mill[isecond]s N`: +/- ms (may exceed 1000).
- `--adjust-sec[ond]s N`: +/- seconds (may exceed 60).
- `--adjust-min[ute]s N`: +/- minutes (may exceed 60).
- `--adjust-h[ou]rs N`: +/- hours (may exceed 24).
- `--adjust-days N`: +/- days.
- `--detect-bad-[camera-]dst`: use RPDP's algorithm to detect a camera whose DST was probably set wrong.

##### Input selection

For the include/exclude flags, use the isolated engine already build and debugged in '../repoint-symlink/github/'. Except add in the expanded glob flags, and the ability to mix-and-match. Then make that a new, better standalone engine in one file in this project, that can be reused by other projects.

- `<source/>` plus optional regex filters (from repoint-symlink, minus the glob flags):
	- By regex:
		- `--inc[lude]="regex"`    : Select files to keep in list, remove everything else. Start with '(?i:...) for case-insensitive.
		- `--exc[lude]="regex"`    : Select files to remove from list.
		- `--re-inc[lude]="regex"` : Select files to re-add to list from the original scan (e.g. a few files deep in a folder nest that were previously excluded too broadly).
	- And/or by glob (may mix both freely):
		- `--[i][whole]name-inc[lude]="*glob*"`    : Select files to keep by filename or whole filepath, with simple wildcards. Wildcards *must be inside the quotes.*
		- `--[i][whole]name-exc[lude]="*glob*"`    : Select files to remove by filename or whole filepath.
		- `--[i][whole]name-re-inc[lude]="*glob*"` : Select files to re-add by filename or whole filepath.
	- When the final file list is compiled, sort it dedup it.
- `--files-from[=]"file"`: take the file list from a file instead of `<source/>`. Mutually exclusive with `<source/>` and inc/exc flags.
	- After loading the list, sort it dedup it.

##### Duplicates detection and transfer

- `--duplicates[=]'skip|source-wins|dest-wins|rename-on-source|rename-on-dest'`: action on a binary duplicate.
	- `rename-on-source` / `rename-on-dest` = keep both, renaming the *source* copy, landed on source or dest respectively. (Verbs are confusing - see Gotchas.)
- `--move[[=]yes|no|true|false|Y|n|t|f|1|0]`: move instead of copy. Default: copy.

##### xattr stash

In case things go sideways:

- `--xattr-og-dt-mdata`: stash original metadata date in xattrs.
- `--xattr-og-dt-mtime`: stash original mtime in xattrs.
- `--xattr-og-filename`: stash original filename in xattrs.

##### output / UX

- `--quiet`: don't print the per-file result.
- `--dry-run` / `-n`: show what would change, write nothing.
- `--confirm`: preview the whole plan in a pager, prompt once y/n, then do it - all from one flag. (Nice companion to `--dry-run`; borrowed from repoint-symlink.)

### Naming logic

- `{DATETIME}` = date/time`[.nnnn]`, derived in this order:
	1. Media metadata "taken/captured" fields.
	2. Else a valid date encoded in the filename itself (suppressed by `--no-filename-date`).
	3. Else mtime (last resort; suppressed by `--no-mtime`).
- `{COUNTER}` = a plausible sequential numeric counter (gaps OK), from either:
	- Leftover digits after `{DATETIME}` is pulled from the filename, or
	- The whole numeric field when there's no `{DATETIME}` in the name.
	- Judged in context of similarly-named files. For example, if all-similar files with 4-5-digit zero-padded characters at the end of the file-prefix ~= definitive counter.
	- Suppressible (`--no-filename-counter`).

### Duplicate detection

#### Logic

Staged, cheapest-check-first, per source file:

1. Find target-folder files with the same size as the source.
2. Of those, compare first and last 128 bytes against the source.
3. Of those still matching, ensure source and each remaining target have valid `user.checksum.blake2b.mtime` and `user.checksum.blake2b.size` xattrs matching their current actual attrs. If stale or missing, run a blake2b checksum (and [re]populate the xattrs).
4. Compare the valid checksums between source and each remaining target. If the source matches one or more of what's left, apply the `--duplicates` action to the source.

#### Cached checksum xattrs

Also generically useful:

- `user.checksum.blake2b`       - the digest.
- `user.checksum.blake2b.mtime` - mtime the digest was computed against.
- `user.checksum.blake2b.size`  - size the digest was computed against.

### Configuration

#### SHCL: "Simple Hierarchical Config Language"

The simplest possible config language that can express any kind of flat or hierarchical data.

CPU cycles are cheap. Brainpower isn't.

SHCL shifts the hard work of using a configuration "language" *away* from:

- The end user.
- The programmer using the code to read frikkin configuration values.

And onto:

- *The parser*. Where it should be.

It's forgiving. It figures things out. It doesn't thow an error and refuse to read the entire config file just because a decimal value didn't have a frikkin' leading '0' in front of '.5'.

Definition:

- Simple heirarchical `[key.]key:value`
	- Comments: '#'
	- Hierarcy defined by one or more of:
		- Keys on subsequent lines at increasing indentation.
			- Any number of tabs OR spaces are allowed; but must be all one or the other in a given file.
		- Sequential keys with "object"-style dot-notation, e.g. `key1.key2.key3: value`
	- Keys are not case-sensitive.
	- Dots and colons can have any amount of tabs or spaces around them.
		- `key1.key1-2:"Joe Smith" == key1 . key1-2  :      "Joe Smith"`
	- It's up to the reader to decide if a key without a value is valid or not. Some keys can purposely just be non-unique organizational "wrappers", that get collapsed together on parsing.
	- A "key path" is defined as a unique combination of keys without their values. Redundant keys are collapsed before parsing. For example, consider this valid jumble (went out of my way to make messy):

		~~~text
		# Indented style
		base               : Chicago
			metrics:
				Population : 30200
				Weather    : Hot,Cold, Lousy , "All around not that great"

		# Inline style
		base:["Cleveland, OH"].metrics.population: 700  # Why only 700?
		base:[Boston].metrics.population                # Empty value. Still type integer.
		base : [ Philly ] . metrics.population: 1024

		# Redundant path
		base               : Chicago
			metrics:
				square-miles: 300
		~~~

	- In all cases above, the common path is: `base.metrics.population`. The above would autoformat to:

		~~~text
		base: "Boston"
			metrics:
				population:
		base: "Chicago"
			metrics:
				population: 30200
				square-miles 300
				weather: "Hot", "Cold", "Lousy", "All around not that great"
		base: "Cleveland, OH"
			metrics:
				population: 700
		base: "Philly"
			metrics:
				population: 1024
		~~~

	- Keys are strings. They can be quoted or not (following generic CSV parsing rules).
	- Values are strongly (but forgivably) typed, as specified by the reader (who consumes the user's settings and defined the schema). Up to key name, default value, comments, and/or context to imply the type to the user.
		- Reader interface:
			- Along with the return value, the read config value method returns sentinel errors such as good (nil), `ErrEmpty`, `ErrKeyPathNotExist`, `ErrInvalidType`. (The last one being a problem but not a reason to not keep reading config.)
	- Value data types:
		- Integer
			- Test value matches: `'^[ \t]*[\"\'][ \t]*CURRENCY?[0-9]+[ \t]*[\"\'][ \t]*$'`
		- A floating-point number
			- The value matches: `'^[ \t]*[\"\'][ \t]*($(?:\d+\.?\d*|\.\d+)|(?:\d+\.?\d*|\.\d+)%|(?:\d+\.?\d*|\.\d+))[ \t]*[\"\'][ \t]*$'`.
			- Note: An integer in the config is also a valid expected float to the reader.
		- A date/time
			- With or without quotes, a robust and accurate date/time function is run on the whitespace and quotes and whitespace-trimmed test value.
			- If it's an unambiguous date and/or time (with or without milliseconds, timezone, 24-hour vs AM/PM, 'nnn' named months, etc.), then:
				- The parser returns to the reader, a date/time.
		- A boolean
			- If the value matches `'^[ \t]*[\"\'][ \t]*(?i:t|true|y|yes|on|enabled|enable|1|f|false|n|no|off|disabled|disable|0)[ \t]*[\"\'][ \t]*$'`, then:
				- The parser returns to the reader, a boolean true or false.
		- An array
			- If there are multiple values separated by commas, then:
				- If the values are all the same type, then:
					- An array of that type is returned to the reader.
				- Values can have any amount of whitespace in-between the commas and values (other that newline).
				- Trailing commas are ignored.
		- A string
			- Anything of the above data types can return as a string, if asked.
			- If the string contains one or more spaces, colon, comma, or embedded quotation marks, it must be enclosed in quotes.
			- Programming quotes rules in effect: Literal unescaped single quotes are valid inside a wrapping double-quote pair, and vice-versa.
			- Spaces *outside* strings are ignored.
			- Escaped characters: \t, \n, \\, \", \'
				- Literal tabs are valid inside quotes (kept) or outside (ignored); but `\t` support is a matter of consistency/familiarity.
				- As a convenience to get around the absolute madness of parsing systems trying to handle escaping double and triple backslashes (etc), any number of literal single backslashes can be substituted by the Unicode charater "ᚠ" (U+16A0 - runic fehu).
					- But if you actually need a runic fehu for some reason, it can be escaped by a backslash: \ᚠ
					- Things can still get complicated (but doable) if you need long combinations of literal ᚠ and \, but this is drastically more rare (and doable) than, say, trying to head-math quintuple-escaped backslashes.
					- It's all about what's easiest and most likely for the *user*, not the parser.
			- The value is obtained by:
				- Trimmed of surrounding whitespace.
				- Any outermost quotes are removed - but not any whitespace within those quotes.
				- Escaped characters are unescaped.
				- The value is returned to the reader as a string.

### For RPDC

- Layered: hard-coded defaults -> user config -> runtime flags.
	- User config under `~/.config`, in YATL
	- Created on first change from a default.
- Camera device -> short-name map:
	- Common devices shipped in a global default config.
	- User overrides and custom devices in the user config.
- Most CLI flags should have a config equivalent.

## Direction decisions

- Language: Go. Single static binary, one for each platform; no runtime dependencies *required*.
	- Although if internal EXIF or video metadata interrogation fails for any given files, the program should try to shell out to ExifTool, if present in the path.
- Two-phase execution (scan/plan, then act) - counter detection needs whole-batch context, and it buys dry-run/confirm/collision-checks cheaply. See Gotchas.

## Plan

## Architecture

### Software stack

- Go. ExifTool optional.

### Saves and persistence

- Checksum cache + original-values stash live in xattrs (with a fallback where xattrs aren't available - see Gotchas).

### UI

- CLI only. `--quiet`, `--dry-run`, `--confirm` (pager preview + single prompt).

### Testing

## Gotchas, forgotten things, and potential solutions

Open questions and things easy to forget. In rough priority order.

### Decide before coding

- How to specify output name template?
	- Probably not part of <output folder name/>, because then it can't go in a generic config file.
	- Ability to named settings would be nice - including system named defaults in global config file.
	- Flag: `--name-template[=]"%DEST%/%YYYY%/%YYYYmmDD%/origs/%SHORT_CAMERA_NAME%_%EXT%/%YYYYmmDD%-%HHMMSS%[.%NNNN%][(%OFFSET:4%)]_%SHORT_CAMERA_NAME%_{%OG_COUNTER%|%COUNTER}:5%.%EXT%"`
		- E.g. "/home/bobs/Pictures/2025/20251231/CanonEOS_dng/20251231-135901(-0700)_CanonEOS_0071.dng"
		- Anything inside a `[]` pair is ignored (including the '[]'), if any part of it contains a missing value.
		- `{}` wraps an `|` ("or") statement, that returns the value from the first valid variable.
		- `\` escapes the characters `{}[]` if they need to be used as literals. (And `\` itself can't be a literal.)
	- Setting (it YATL):
		NamedTemplates:
			default: "%DEST%/%YYYY%/%YYYYmmDD%/origs/%SHORT_CAMERA_NAME%_%EXT%/%YYYYmmDD%-%HHMMSS%[.%NNNN%][(%OFFSET:4%)]_%SHORT_CAMERA_NAME%_{%OG_COUNTER%|%COUNTER}:5%.%EXT%"

- Dest layout - flat into `<dest/>`, or fan out a date tree (`%YYYY%/%YYYYmmDD%/...`) like the bash version? Big call, drives everything downstream. Lean: config-selectable, flat by default.

- Two-phase run (scan/plan -> execute) - counter detection is contextual so we can't stream file-by-file. One scan pass also gives dry-run, `--confirm` preview, name-collision detection, and a free-space check almost for free. Make it the backbone.

- Name collisions that AREN'T binary dupes - two different files can compute the same target name (same second, no counter, e.g. bursts). `--duplicates` only covers binary dupes. Need a separate disambiguator: subsecond -> extend counter -> `_a`/`_b`.

### Media edge cases

- Sidecars / companions - RAW+JPEG pairs, `.XMP`, `.AAE` (iOS edits), `.THM`, GoPro `.LRV`, Live Photos (HEIC+MOV). Detect as a group and rename/move together with the same `{DATETIME}` so the link survives. Add a `--sidecars` policy.
- Timezone / DST - EXIF `DateTimeOriginal` has no zone; MP4/QuickTime is UTC; newer EXIF has `OffsetTimeOriginal`. Pin the reference frame, and decide whether `--adjust-*` and `--detect-bad-dst` run before or after zone normalization, and whether they hit all sources or only metadata dates.
- Field priority for `{DATETIME}` - write the ordered list explicitly (e.g. `SubSecDateTimeOriginal` -> `DateTimeOriginal` -> `CreateDate` -> QuickTime `CreationDate` -> GPS date). "Common fields" is too vague to code.
- Subsecond / bursts - `SubSecTimeOriginal` is the clean way to split same-second shots before falling back to a counter.
- Metadata lib decision - pure-Go (fast, static, narrower format coverage) vs shell out to exiftool (huge coverage, external dep, slow). Affects the static-binary goal; decide now.

### Safety (especially --move)

- Atomic write - copy to a temp name, fsync, then rename to final. Never leave a half-written file at the real name. Trap SIGINT/SIGTERM and clean up temps.
- Verify before delete on move - check size/checksum after the copy, then unlink the source. A silent bad move of irreplaceable photos is the worst outcome.
- Undo - the `--xattr-og-*` stashes are useless with no way to use them. Write a per-run manifest and add `--undo <manifest>`.
- Idempotency / resume - a re-run should skip already-conformant files and pick up where it left off, like the bash version.

### Cross-platform

- xattrs don't exist on FAT/exFAT - which is exactly what SD cards are, usually the source. The whole checksum-cache + og-stash scheme needs a fallback (skip cache? sidecar db? Windows ADS?).
- reflink is filesystem-specific (btrfs/XFS/APFS/ReFS) and never applies cross-filesystem, so SD -> array is always a real copy. `--reflink=auto` degrade-to-copy is fine, just don't expect it on the main path.
- Bad target names - Windows reserved (`CON`, `NUL`), `:`, the 260-char path limit, case-insensitive collisions (`IMG.JPG` vs `img.jpg`), Unicode NFC/NFD (macOS). Sanitize and collision-check.
- Set target mtime to `{DATETIME}`? - often want the filesystem date to match capture date. Make it a flag.

### Loose ends in the current flags

- `--duplicates` verbs are confusing (already caught: "rename-on-target = rename the source on the target"). Consider `keep-both-in-source` / `keep-both-in-dest`.
- `--move` default is copy; a `--move`/`--copy` pair may read cleaner than a tri-state value flag.
- `--files-from` - allow `-` (stdin) and a NUL-delimited variant (`--files-from0` / print0-style) so odd filenames survive.
- Binary name - syntax says `dpdc`, but the repo is rapid-photo-downloader-**cli** (`rpdc`?). Pick one.
- End-of-run summary + meaningful exit codes, plus an optional `--json` output mode for scripting.
- `--on-error=skip|abort` (+ retry on flaky SD reads).
- Recursion depth, and whether inc/exc match basename, relative path, or full path (repoint has `--inc-target`/`--exc-target` for the target side).

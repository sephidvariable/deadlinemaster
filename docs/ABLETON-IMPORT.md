# Ableton-aware folder import

Sources checked 2026-10-29:
- https://help.ableton.com/hc/en-us/articles/115000915804-Saving-Projects
- https://www.ableton.com/en/manual/managing-files-and-sets/

Ableton documents Ableton Project Info, Backup, and Samples, and allows related versions of a Set in a single project. Its manual describes .asd analysis sidecars.

Recognition is a heuristic: a folder with one or more direct .als files and a direct Ableton Project Info or Samples directory. The recursive scan supports a selected parent containing multiple Live projects. Backup and Samples are not required together. An unrecognized folder prompts the user to choose another folder or import anyway.

Import excludes .als and .asd files, recognized nested project folders entirely, and Samples, Backup and Ableton Project Info directly inside a recognized project. When the selected root itself is a Live project, its other files and folders (such as Exports) are retained. No source files are changed.

This is not ALS content parsing. Custom production folders are not reliably distinguishable from deliverables; arbitrary WAV files are not classified as final masters. Exports inside excluded production folders are excluded too. Existing library projects are not rescanned or modified.

Folder imports and Add files now accept only the audio/document extensions in ImportFileTypes. Matching is case-insensitive. Folder scans prune empty/unsupported-only directories; Pages and RTFD packages are linked intact as documents. Ableton recognition still runs before filtering. Existing imported assets are unchanged. Import support does not imply native playback, conversion, or brief-text extraction support for every format.

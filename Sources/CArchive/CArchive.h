// The part of libarchive's reading API that EPUBKit uses for comic archives (CBR). macOS ships
// libarchive as a system library (libarchive.tbd in the SDK, /usr/lib/libarchive.2.dylib) but
// not its header, so the few declarations needed are written here, as in libarchive's
// archive.h and archive_entry.h (BSD licence). Nothing of libarchive is bundled with the app.
// Author: Rocco Casadei, a.k.a. Roccobot

#ifndef CARCHIVE_H
#define CARCHIVE_H

#include <stddef.h>
#include <sys/types.h>

struct archive;
struct archive_entry;

#define ARCHIVE_EOF 1
#define ARCHIVE_OK 0
#define ARCHIVE_RETRY (-10)
#define ARCHIVE_WARN (-20)
#define ARCHIVE_FAILED (-25)
#define ARCHIVE_FATAL (-30)

#define AE_IFMT 0170000
#define AE_IFREG 0100000

struct archive *archive_read_new(void);
int archive_read_support_format_rar(struct archive *);
int archive_read_support_format_rar5(struct archive *);
int archive_read_support_format_7zip(struct archive *);
int archive_read_open_filename(struct archive *, const char *filename, size_t block_size);
int archive_read_next_header(struct archive *, struct archive_entry **);
ssize_t archive_read_data(struct archive *, void *, size_t);
int archive_read_data_skip(struct archive *);
int archive_read_free(struct archive *);
const char *archive_error_string(struct archive *);

const char *archive_entry_pathname(struct archive_entry *);
const char *archive_entry_pathname_utf8(struct archive_entry *);
mode_t archive_entry_filetype(struct archive_entry *);
int archive_entry_is_encrypted(struct archive_entry *);

#endif

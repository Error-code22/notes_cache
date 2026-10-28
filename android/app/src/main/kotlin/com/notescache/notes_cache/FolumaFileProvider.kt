package com.notescache.notes_cache

import androidx.core.content.FileProvider

/** Separate provider so plugin FileProviders can keep their own authorities. */
class FolumaFileProvider : FileProvider()

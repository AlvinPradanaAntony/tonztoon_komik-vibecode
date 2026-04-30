# TonzToon Flutter Frontend

Vertical slice frontend for the existing TonzToon FastAPI backend.

## Run

Start the backend first, then run the app:

```sh
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

Use `10.0.2.2` for Android emulator. For iOS simulator or desktop, use the
backend host that can be reached from that runtime, for example:

```sh
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

## Implemented Slice

- Home with source picker, new releases, popular comics, pull-to-refresh, and
  cached fallback.
- Comic detail with metadata, chapter list, and Read/Continue CTA.
- Vertical reader with zero-gap image list, temporary overlay, retry on failed
  page image, prev/next chapter, progress restore, and progress persistence.
- Guest local progress via Hive and logged-in cloud progress via backend bearer
  token.
- Email/password auth through backend; Google OAuth is intentionally disabled
  for this slice.
- Search screen backed by `GET /search`.
- Library tabs for bookmarks, collections, favorite scenes, history, and
  download wishlist.
- Comic Detail CTAs for bookmark, collection picker/create collection, and
  queueing download wishlist.
- Reader settings for default mode, LTR/RTL, auto-next preference, and cache
  clearing.
- Reader vertical/paged toggle and long-press favorite scene saving.
- Actual offline chapter file download to app documents storage, offline reader
  fallback, per-chapter delete, and clear-all offline storage.
- Fine-grained offline queue controls with live batch progress percentages,
  current chapter status, batch cancel, and completed batch removal.
- Background-resumable download handling: interrupted batches are persisted as
  paused and automatically resumed on app bootstrap, continuing from the next
  unfinished chapter.
- Guest-to-cloud migration dialog after login using `/library/sync/import`.
- Collection rename and delete from the Library tab.

## Still Pending

- Google OAuth activation.
- Native OS-level background downloads that continue while the process is fully
  terminated by the system.

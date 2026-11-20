# Task List

Flutter task list with login, server-side persistence and an animated
completion effect, built over three assignments of the Smartphone Software
course at UFRJ. The whole app lives in a single `main.dart` so it runs as-is
in DartPad.

## Features

- **Sign up and log in** against the course's REST API. A wrong password
  shows the API's message; an unknown email offers the sign-up screen.
- **Tasks saved to the server** on every change, tied to the logged-in user.
- **Completed tasks sink to the bottom.** The most recently completed one
  becomes the first of the completed group; uncompleting a task moves it to
  the end of the pending ones.
- **Delayed delete with undo.** Deleting turns the row red for three seconds
  and swaps the delete button for *Desfazer* (undo). Several rows can be
  counting down at once.
- **Swipe actions.** Swipe right to complete, left to delete (same delayed
  delete as the button).
- **Animated completion.** The completed task lifts off, slides over the list
  to its new position and tilts on the way down, levelling out as it lands.

## How the completion animation works

The list is a single `AnimatedList`, wrapped in a `Stack` together with a
floating copy of the row being moved.

When a task is completed, three things start at the same time and share the
same duration and curve:

1. `removeItem` collapses the row's old slot.
2. `insertItem` opens a slot at the new position. The real row is already
   there but kept invisible.
3. A copy of the row is drawn on top of the list with `AnimatedPositioned`,
   travelling from the old slot to the new one, while a
   `TweenAnimationBuilder` rotates it by `sin(πt)` — zero at both ends, peak
   tilt halfway, so it tips and then straightens.

When the copy lands, it is removed and the real row becomes visible in
exactly the same place. Because the list has fixed row heights, both
positions are just `index × rowHeight`. The destination is recomputed on
every build, so if another task is deleted mid-flight the copy simply
retargets.

Only completion is animated. Uncompleting, adding and deleting update the
list instantly.

## Server sync

The app talks to a PostgREST API provided by the course. Requests go through
the browser's own `fetch`, called from Dart with `dart:js_interop`, so the app
needs no packages beyond Flutter itself and runs in any DartPad without
editing `pubspec.yaml`.

| Action | Request |
|---|---|
| Sign up | `POST /rpc/registra_usuario` |
| Log in | `POST /rpc/fazer_login` → JWT valid for 5 minutes |
| Load tasks | `GET /tarefas` — `[]` means the user has no list yet |
| First save | `POST /tarefas` with `{email, valor}` |
| Later saves | `PATCH /tarefas?email=eq.<email>` with `{valor}` |

Every call to `/tarefas` carries `Authorization: Bearer <token>`, and any
`401` sends the user back to the login screen.

Two details of the API shape the save logic. `PATCH` answers `204` even when
its filter matches nothing, so the request asks for
`Prefer: return=representation` and checks whether any row came back. And
`POST` answers `409` when the list already exists. Each path falls back to
the other, so saving keeps working if the list is created or removed on the
server while the app is open.

Tasks are stored as `{titulo, concluida, ordem}`, where `ordem` is the row's
position, so the list reloads in the same order.

## Files

| File | Description |
|---|---|
| `lib/main.dart` | The whole app: API calls, login, sign-up and task list screens |
| `pubspec.yaml` | Project metadata — no packages beyond Flutter |

## Running

**DartPad:** paste `lib/main.dart` into [dartpad.dev](https://dartpad.dev) and
run it. Nothing else to configure.

**Locally** (web only, since requests use the browser's `fetch`):

```bash
flutter create .      # generates the platform folders, keeps lib/main.dart
flutter pub get
flutter run -d chrome
```

## Stack

Dart · Flutter · Material 3 · `dart:js_interop` · PostgREST

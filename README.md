# Live Poll: a Terraform demo you can vote on

A QR code on the projector, the room votes from their phones, and Terraform controls the question, the options and the vote store. Every Terraform change shows up on 20 phones.

- **What and why:** [SPEC.md](SPEC.md)
- **How to present it:** `RUNBOOK.md` (coming in M5)

## Run the app locally

```sh
cd app
docker compose up          # the app + Azurite (Azure's storage emulator)
open http://localhost:8000/results
```

Change the poll: `POLL_QUESTION="Tabs or spaces?" POLL_OPTIONS="Tabs|Spaces" docker compose up -d app`

## Test

```sh
pip install -r app/requirements-dev.txt
pytest app/tests
```

## Layout

| Folder | What |
|---|---|
| `app/` | the poll (FastAPI, Azure Table Storage) |
| `bootstrap/` | run once: state storage, resource groups, CI identity (M2) |
| `infra/` | the Terraform the room reads, for dev and prod (M3) |

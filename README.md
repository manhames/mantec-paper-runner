# MANTEC Paper Runner (DigitalOcean Noob Guide)

This repo is a tiny ops wrapper to run your **MANTEC paper trading** in Docker for 2 weeks.

## 0) Where this repo should live

Use this folder:
- `C:\Users\MAX\mantec-paper-runner`

Keep it separate from:
- `C:\Users\MAX\MANTEC`

Do not put one repo inside the other.

## 1) Push this small repo (one time)

From your Windows PowerShell:

```powershell
Set-Location C:\Users\MAX\mantec-paper-runner
git add .
git commit -m "add droplet bootstrap and runbook"
git remote add origin https://github.com/manhames/mantec-paper-runner.git
git push -u origin main
```

Also ensure your main strategy repo (`MANTEC`) is on GitHub/GitLab so the droplet can clone it.

## 2) Create the DigitalOcean droplet

In DigitalOcean UI:
1. `Create` -> `Droplets`
2. Image: `Ubuntu 24.04 LTS`
3. Size: start with at least `4 vCPU / 8 GB RAM` (more if you refresh large features often)
4. Storage: `100 GB` recommended
5. Authentication: SSH key (recommended) or password
6. Create droplet and copy the public IP

## 3) SSH into droplet

From Windows PowerShell:

```powershell
ssh root@<DROPLET_IP>
```

## 4) Clone this small repo on droplet

On droplet shell:

```bash
cd /opt
git clone https://github.com/manhames/mantec-paper-runner.git mantec-paper-runner
cd /opt/mantec-paper-runner
chmod +x bootstrap_droplet.sh runbook.sh
```

## 5) Run one-shot bootstrap (copy-paste exactly)

On droplet shell (replace values):

```bash
MANTEC_REPO_URL="https://github.com/manhames/mantec-paper-core.git" \
COINGECKO_API_KEY="<YOUR_COINGECKO_PRO_KEY>" \
PAPER_RUNTIME_HOURS="336" \
TOTAL_NET_WORTH_USD="100000" \
TEST_ALLOC_FRACTION="0.01" \
bash /opt/mantec-paper-runner/bootstrap_droplet.sh
```

What this does:
1. Installs Docker + Compose plugin
2. Clones/updates MANTEC at `/opt/mantec`
3. Creates/updates `/opt/mantec/analysis/real_world_testsing/.env`
4. Runs a container smoke test
5. Starts Docker paper stack

## 6) Watch logs

```bash
cd /opt/mantec
docker compose -f analysis/real_world_testsing/docker-compose.paper.yml logs -f paper_bot
```

## 7) Daily operations (simple)

Use helper script:

```bash
/opt/mantec-paper-runner/runbook.sh status
/opt/mantec-paper-runner/runbook.sh logs
/opt/mantec-paper-runner/runbook.sh restart
/opt/mantec-paper-runner/runbook.sh stop
```

## 8) Download results back to your laptop

From Windows PowerShell:

```powershell
scp root@<DROPLET_IP>:/opt/mantec/analysis/real_world_testsing/live_cycle_report.csv C:\Users\MAX\Downloads\
scp root@<DROPLET_IP>:/opt/mantec/analysis/real_world_testsing/live_ledger.csv C:\Users\MAX\Downloads\
scp root@<DROPLET_IP>:/opt/mantec/analysis/real_world_testsing/latest_status.md C:\Users\MAX\Downloads\
```

## Notes

- This setup is **paper mode only** (`LIVE_EXECUTION=false`).
- Keep `TEST_ALLOC_FRACTION <= 0.01`.
- If your main repo is private, make sure droplet can clone it (SSH key or PAT).

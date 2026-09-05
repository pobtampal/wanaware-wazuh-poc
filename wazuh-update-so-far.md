# Wazuh evaluation — what we've done and where we stand

*Plain-language update for management · 2026-09-05*

## Bottom line
We've set up the security-monitoring tool we're evaluating (called Wazuh), connected a test laptop, and confirmed it works — it collects useful security information and sends the team an alert within seconds when something notable happens. On paper, we've also mapped out how a full rollout (~2,000 machines) would be built and what it would cost, which comes out far cheaper than a comparable commercial tool. We're now waiting on a few access approvals from other teams to finish the last pieces — and the system is ready to demonstrate live.

## Where things stand right now (at a glance)
- ✅ The tool is set up and **running and healthy**.
- ✅ A **test laptop is connected and reporting continuously**.
- ✅ We **tested the alerts live — they work**, and arrive in seconds.
- ✅ We've **worked out the full-scale design and cost on paper**.
- ⏳ We're **waiting on a few access approvals from other teams** before we can finish — and it's **ready to demo** now.

*For the specifics of what still remains, see the companion status document (`wazuh-poc-status-snapshot.md`).*

## What's been done and proven to work
- **The system is running and healthy** — all parts online, no faults.
- **One test laptop is connected and reporting non-stop** to the central system.
- We can see genuinely useful security information from it — for example:
  - when an **important file is changed**,
  - **software installed that has known security weaknesses**,
  - **risky sign-in attempts**, such as repeated failed password entries for admin access.
- **Alerts reach the team in Slack within seconds**, and we tested this for real. In the rehearsal, a failed secure-login attempt produced a Slack notification in **a few seconds**, and a change to a watched file was **flagged automatically**. After testing, we **put the system back to its normal everyday settings** (confirmed).

## What we've worked out on paper
- **Full rollout (~2,000 machines):** we designed how it would be built and estimated the running cost at roughly **$40,000–$145,000 a year**. For comparison, a commercial tool at that scale runs roughly **$285,000–$435,000 a year** — so this is about **3 to 7 times cheaper**. (The software itself is free; most of the cost is the staff time to run it.)
- **Updates and maintenance:** we tested **applying an update and undoing it cleanly**, and tested **backing up the data** — so routine upkeep is understood, not a question mark.

## Honest notes worth knowing
- **This tool watches for and reports on threats, but it is not itself an antivirus.** It works *alongside* antivirus; it doesn't replace it. For full protection we'd still keep a dedicated antivirus/endpoint product in place.
- **A couple of things work differently on Mac computers:** some checks (like watching files for changes) run on a schedule rather than instantly, and getting the fullest information from a Mac needs one extra setup step. This is mostly a Mac quirk and doesn't apply the same way to Windows or Linux.
- The figures above come from **a single test laptop**. Real-world numbers (how much data, how much storage) will be firmed up once more machines and data sources are connected — which is part of what we're waiting on approvals for.

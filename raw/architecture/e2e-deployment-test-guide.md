# TRH Platform E2E Deployment Test Guide

| This is an internal document to establish the testing criteria for mainnet testing phase 1.

## Testing Scope
- L1 Contract deployment
- L2 deployment including bridge infrastructure
- Block explorer & operation tools (monitoring, backup, system pulse) deployment
- Network operation for stability testing
- Real-time monitoring and metrics collection
- Disaster recovery drill execution

## Prerequisites

| Item | Requirement |
|------|------------|
| Browser | Latest version of Chrome |
| Platform Access | Access to `http://<server-address>:3000` |
| Account | Email/password for login |
| RPC URL | L1 Execution Layer URL, L1 Beacon Chain URL (pre-registered or direct input) |
| AWS Credentials | AWS Access Key registered in Configuration |
| Seed Phrase | 12-word BIP39 mnemonic (can be auto-generated for testing) |
| ETH Balance | Sufficient ETH in each account (Admin, Proposer, Batcher, Sequencer) |
| (Optional) API Keys | CoinMarketCap API Key, WalletConnect Project ID |

---

## Phase 0: Login / Authentication

> Verify that the platform is accessible and authentication works correctly.

| ID | Test Item | Test Procedure | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------|---------------------|-----------|
| T0-1 | Login page access | Navigate to `http://<server-address>:3000` | Login page (`/auth`) renders correctly | |
| T0-2 | Successful login | Enter valid email/password and click login | Redirected to dashboard (`/dashboard`), sidebar is displayed | |
| T0-3 | Invalid credentials | Attempt login with incorrect password | Error message is displayed, remains on login page | |
| T0-4 | Unauthenticated page access | Access `/rollup` directly while logged out | Redirected to `/auth` | |

---

## Phase 1: Pre-Configuration

> Register required credentials before creating a rollup.

### 1-1. Register RPC URLs

1. Left sidebar → Click **Configuration**
2. Select **RPC URLs** tab
3. Click **Add RPC URL** button
4. Enter the following:

| Field | Example Value |
|-------|--------------|
| Name | A recognizable name (e.g., "Sepolia EL") |
| RPC URL | `https://eth-sepolia.g.alchemy.com/v2/...` |
| Type | Execution Layer or Beacon Chain |
| Network | Testnet or Mainnet |

5. Click **Save**
6. Register a Beacon Chain URL using the same steps

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T1-1 | Register RPC URL | After saving, the URL appears in the list with its name and type | |
| T1-2 | Duplicate URL prevention | Re-registering the same URL shows an error or duplicate warning | |
| T1-3 | Invalid URL input | Entering an invalid URL shows a validation error | |
| T1-4 | Delete RPC URL | Deleting a registered URL removes it from the list | |

### 1-2. Register AWS Credentials

1. Select **AWS Credentials** tab
2. Click **Add Credential**
3. Enter the following:

| Field | Description |
|-------|-------------|
| Name | Identifier name |
| Access Key ID | AWS Access Key |
| Secret Access Key | AWS Secret Key |

4. Click **Save**

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T1-5 | Register AWS credentials | After saving, the credential appears in the list with its name | |
| T1-6 | Secret Key masking | Secret Access Key is displayed as masked (`****`) in the list | |
| T1-7 | Delete AWS credentials | Deleting a credential removes it from the list | |

### 1-3. Register API Keys (Required for Block Explorer)

1. Select **API Keys** tab
2. Click **Add API Key**
3. Register CoinMarketCap API Key (Type: CMC)
4. Click **Save**

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T1-8 | Register API key | After saving, the API key appears in the list with its type | |
| T1-9 | Delete API key | Deleting an API key removes it from the list | |

---

## Phase 2: L1 Contract Deployment + L2 Deployment (Rollup Creation)

> Create a rollup through the 4-step wizard. L1 contract deployment and L2 infrastructure provisioning proceed automatically.

### 2-1. Start Creation

1. Left sidebar → Click **Rollup**
2. Click **Deploy New Stack** button in the top-right corner

### 2-2. Step 1 — Network & Chain

| Field | Input | Notes |
|-------|-------|-------|
| Network | Select **Testnet** | Select from dropdown |
| Chain Name | Enter a name starting with a letter | Max 14 chars, letters/numbers/spaces only |
| L1 RPC URL | Select registered URL or enter manually | Selectable from dropdown |
| L1 Beacon URL | Select registered URL or enter manually | Selectable from dropdown |

- (Optional) Toggle **Show Advanced Configuration** → Adjust L2 Block Time, Batch Submission Frequency, etc.
- Verify inputs in the **Configuration Summary** card at the bottom
- Click **Next**

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T2-1 | Wizard entry | Clicking Deploy New Stack renders the Step 1 screen correctly | |
| T2-2 | Chain Name validation | Entering names exceeding 14 chars, containing special characters, or starting with a number shows an error | |
| T2-3 | RPC connection verification | Entering a valid RPC URL triggers automatic connection verification and passes | |
| T2-4 | Invalid RPC URL rejection | Entering an invalid RPC URL fails verification, Next button is disabled | |
| T2-5 | Configuration Summary display | Entered Network, Chain Name, and RPC URL are accurately displayed in the Summary card | |
| T2-6 | Advanced Configuration | Toggling ON reveals additional fields such as L2 Block Time | |

### 2-3. Step 2 — Account & AWS

**Seed Phrase Input:**
1. Enter 12 words in order, or click **Generate Random** to auto-generate
2. Check the yellow checkbox "I have written down my seed phrase..."

**Account Selection:**

| Role | Description |
|------|-------------|
| Admin Account | Administrator account (select from dropdown) |
| Proposer Account | Proposer account (different from Admin) |
| Batch Account | Batch submitter account (different from above) |
| Sequencer Account | Sequencer account (different from above) |

> All 4 accounts must be **different from each other**.

**AWS Settings:**
1. AWS Access Key → Select registered credential
2. AWS Region → Available regions auto-populate, select one

Click **Next**

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T2-7 | Seed Phrase auto-generation | Clicking Generate Random generates and fills 12 words automatically | |
| T2-8 | Seed Phrase checkbox required | Next button is disabled when checkbox is unchecked | |
| T2-9 | Duplicate account rejection | Selecting the same account for multiple roles shows an error or prevents selection | |
| T2-10 | AWS region auto-loading | Selecting an AWS credential populates available regions in the dropdown | |

### 2-4. Step 3 — DAO Candidate (Optional)

- If DAO candidate registration is not needed → Click **Skip this step**
- To register: Enter Amount (minimum 1000.1 TON) and Memo, then click **Next**

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T2-11 | DAO skip | Clicking Skip this step navigates to Step 4 correctly | |
| T2-12 | DAO minimum amount validation | Entering less than 1000.1 TON shows an error message | |

### 2-5. Step 4 — Review & Deploy

1. Verify all settings in the **Configuration Summary** card
2. Check estimated gas cost (ETH) in the **Estimated Deployment Cost** card
3. (Optional) Check **Enable automatic backup** checkbox → Enable auto backup
4. Click **Deploy Rollup**
5. In the **Pre-Deployment Checklist** dialog, check all 4 items:
   - [ ] RPC Connection Verified
   - [ ] Account Balances Sufficient
   - [ ] AWS Credentials Validated
   - [ ] Configuration Reviewed
6. Click **Confirm & Deploy**

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T2-13 | Review screen accuracy | All values entered in Steps 1-3 are accurately displayed in the Summary | |
| T2-14 | Estimated gas cost display | Estimated Deployment Cost card shows a gas cost in ETH greater than 0 | |
| T2-15 | Incomplete checklist blocking | Confirm & Deploy button is disabled if any of the 4 checklist items is unchecked | |
| T2-16 | Deployment start confirmation | After clicking Confirm & Deploy, user is redirected to the rollup list page | |
| T2-17 | Deploying status display | The created rollup appears in the list with **Deploying** status | |
| T2-18 | Deployment History refresh | Clicking the rollup → Deployment History tab shows progress auto-refreshing every 10 seconds | |
| T2-19 | Deployment completion | After deployment completes, status changes to **Deployed** (may take several minutes to tens of minutes) | |

---

## Phase 3: Bridge Infrastructure Deployment

> After L2 deployment is complete, install the Bridge.

1. Rollup detail page → Click **Integrations** tab
2. In **Available Components** section, click **Install** on the **Bridge** card
3. Confirmation dialog → Click **Install**

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T3-1 | Bridge installation start | After clicking Install, the Bridge card appears in **Active Integrations** | |
| T3-2 | Bridge installation complete | Status changes from InProgress to **Completed** | |
| T3-3 | Deployment History record | "Install Bridge" entry is added to the Deployment History tab | |
| T3-4 | Token Bridge link activation | **Token Bridge** link appears in the Overview tab and loads the Bridge page when clicked | |

---

## Phase 4: Block Explorer & Operations Tools Deployment

### 4-1. Block Explorer Installation

1. **Integrations** tab → Click **Install** on the **Block Explorer** card
2. Enter the following in the configuration form:

| Field | Value |
|-------|-------|
| Database Username | Desired DB username |
| Database Password | Password with 9+ characters |
| CoinMarketCap API Key | Select registered CMC API key or enter manually |
| WalletConnect Project ID | WalletConnect project ID |

3. **Continue** → Click **Confirm** in the confirmation dialog

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T4-1 | Block Explorer installation complete | Status changes to **Completed** | |
| T4-2 | DB password length validation | Entering a password shorter than 9 characters shows an error message | |
| T4-3 | Explorer link activation | **Block Explorer** link appears in the Overview tab | |
| T4-4 | Explorer page access | Clicking the Block Explorer link loads the page successfully (HTTP 200) | |

### 4-2. Monitoring (Grafana) Installation

1. **Integrations** tab → Click **Install** on the **Monitoring** card
2. Fill in the configuration form:

| Section | Field | Value |
|---------|-------|-------|
| Grafana | Grafana Password | Password with 8+ characters |
| Logging | Enable logging | ON (default) |
| Telegram Alerts (Optional) | Toggle ON → Enter Bot API Token and Chat ID |
| Email Alerts (Optional) | Toggle ON → Enter SMTP server, sender email, SMTP password, recipient email |

3. **Continue** → Click **Confirm**

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T4-5 | Monitoring installation complete | Status changes to **Completed** | |
| T4-6 | Grafana password length validation | Entering a password shorter than 8 characters shows an error message | |
| T4-7 | Grafana link activation | **Grafana Dashboard** link appears in the Overview tab | |
| T4-8 | Grafana dashboard access | Clicking the Grafana link → Login is possible with the password set during installation | |
| T4-9 | Telegram alert reception (Optional) | Test alert is received in the Telegram bot when configured | |
| T4-10 | Email alert reception (Optional) | Test email is delivered to the recipient when configured | |

### 4-3. System Pulse (Uptime) Installation

1. **Integrations** tab → Click **Install** on the **System Pulse** card
2. Confirmation dialog → Click **Install**

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T4-11 | System Pulse installation complete | Status changes to **Completed** | |

### 4-4. Backup Configuration

1. Click **Backup** tab
2. Check the **Backup Configuration** card on the right
3. Configure Auto Backup toggle, backup time, and retention period
4. Click **Configure Backup**

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T4-12 | Backup configuration saved | Success toast message appears after clicking Configure Backup | |
| T4-13 | Protected status display | Backup Status card shows a **Protected** badge | |
| T4-14 | Backup info display | Region, Namespace, and other configuration info are displayed in the Status card | |

---

## Phase 5: Network Stability Verification

> Verify that the deployed rollup is functioning correctly.

### 5-1. Basic Status Check

1. Rollup detail → **Overview** tab
2. Verify the following:

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T5-1 | L1 Chain info display | Layer 1 / L1 Chain ID shows correct network information | |
| T5-2 | L2 Chain info display | Layer 2 / L2 Chain ID shows the created L2 chain information | |
| T5-3 | RPC URL display | L2 RPC URL link is displayed and clickable | |
| T5-4 | Quick Links activation | Block Explorer, Token Bridge, and Grafana links are all active | |

### 5-2. Settings Verification

1. Click **Settings** tab

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T5-5 | RPC URL display | L1 RPC URL and L1 Beacon URL are displayed correctly | |
| T5-6 | Read-only fields | L2 Block Time and Challenge Period are displayed as read-only (grayed background) and cannot be modified | |

### 5-3. RPC URL Change Test

1. In the **Settings** tab, change L1 RPC URL to a different valid URL
2. Click **Update Configuration**

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T5-7 | RPC URL change success | Success toast message appears after clicking Update Configuration | |
| T5-8 | Changed value persistence | The changed URL persists after page refresh | |
| T5-9 | Invalid URL change rejection | Entering an invalid URL shows an error message and save fails | |

---

## Phase 6: Real-Time Monitoring & Metrics Collection

### 6-1. Grafana Dashboard Verification

1. Overview tab → Click **Grafana Dashboard** link
2. Log in to Grafana (use the password set during installation)

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T6-1 | Node status metrics | Node status metrics are being collected and data points are displayed in graphs | |
| T6-2 | Block production indicators | Block production metrics (block height, creation time, etc.) are displayed | |
| T6-3 | Resource usage | CPU, memory, and other resource usage graphs show non-zero values | |

### 6-2. Deployment Log Verification

1. Click **Deployment History** tab
2. Click the **Logs** icon on the latest deployment entry
3. Verify log content in the log dialog
4. Click the **Download** icon to download the log file

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T6-4 | Real-time log refresh | New log lines are appended in the log dialog at 5-second intervals | |
| T6-5 | Log file download | Clicking Download downloads a `.log` file with non-empty content | |

### 6-3. Alert Testing (Optional)

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T6-6 | Telegram alert reception | Alert message is received in the Telegram bot (delivered to the configured Chat ID) | |
| T6-7 | Email alert reception | Alert email is delivered to the configured recipient address | |

---

## Phase 7: Disaster Recovery Drill

> Test the full process of restoring data from backups.

### 7-1. Snapshot Creation

1. Click **Backup** tab
2. Click **Create Snapshots** button
3. Wait for the progress dialog to complete

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T7-1 | Snapshot creation complete | Progress dialog changes to completed state and shows success message | |
| T7-2 | Snapshot list display | New snapshot appears in the **Recent Snapshots** card | |
| T7-3 | Snapshot metadata | Vault Name, Recovery Point ARN, and creation time are all displayed | |

### 7-2. Restore from Backup

1. Click **Restore from Backup** button
2. Select the recently created snapshot from the **Recovery Point** dropdown
3. (Optional) Check **Automatically attach workloads** → Auto-attach workloads after restore
4. Click **Restore**
5. Wait for the progress dialog to complete

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T7-4 | Restore complete | Restore process completes without errors | |
| T7-5 | Sync notice display | Sync notification message is displayed on screen after restore completes | |
| T7-6 | Rollup recovery | Rollup status returns to normal (**Deployed**) after restore | |

### 7-3. Storage Attach Test

1. Click **Attach to New Storage** button
2. Enter the following:

| Field | Description |
|-------|-------------|
| EFS ID | Format: `fs-xxxxxxxxxx` |
| PVCs | PVC names (comma-separated) |
| STSs | StatefulSet names (comma-separated) |

3. (Recommended) Check **Back up PV/PVC definitions before attach** → Click **Generate & Download Backup**
4. Click **Attach**

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T7-7 | PV/PVC backup download | Clicking Generate & Download Backup downloads a backup file (`.zip`) | |
| T7-8 | Storage attach complete | Success message appears after clicking Attach, storage is connected successfully | |
| T7-9 | Invalid EFS ID rejection | Entering an invalid EFS ID format shows an error message | |

---

## Phase 8: Cleanup

### 8-1. Integration Component Removal

1. **Integrations** tab → Click **Uninstall** on installed components
2. Click **Confirm** in the confirmation dialog

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T8-1 | Component removal complete | After uninstalling, the component is removed from Active Integrations | |
| T8-2 | Related link deactivation | The Quick Link for the removed component disappears from the Overview tab | |

### 8-2. Rollup Deletion

1. Navigate to the rollup list page
2. Click **Delete** (or **Terminate**) on the target rollup
3. Confirm in the confirmation dialog

| ID | Test Item | Acceptance Criteria | Pass/Fail |
|----|-----------|---------------------|-----------|
| T8-3 | Deletion status transition | Status changes from **Terminating** to **Terminated** | |
| T8-4 | AWS resource cleanup | EKS/EC2/EFS and other resources for the rollup are deleted or cleaned up in the AWS console | |

---

## Full Checklist Summary

| Phase | Test IDs | Test Items | Pass/Fail |
|-------|----------|-----------|-----------|
| 0 | T0-1~T0-4 | Login, authentication, redirect | |
| 1 | T1-1~T1-4 | RPC URL registration/deletion/validation | |
| 1 | T1-5~T1-7 | AWS credentials registration/masking/deletion | |
| 1 | T1-8~T1-9 | API key registration/deletion | |
| 2 | T2-1~T2-6 | Wizard Step 1 - Network & Chain setup | |
| 2 | T2-7~T2-10 | Wizard Step 2 - Account & AWS setup | |
| 2 | T2-11~T2-12 | Wizard Step 3 - DAO Candidate | |
| 2 | T2-13~T2-19 | Wizard Step 4 - Review & Deploy, deployment completion | |
| 3 | T3-1~T3-4 | Bridge installation and link verification | |
| 4 | T4-1~T4-4 | Block Explorer installation and access verification | |
| 4 | T4-5~T4-10 | Monitoring installation, Grafana access, alert reception | |
| 4 | T4-11 | System Pulse installation | |
| 4 | T4-12~T4-14 | Backup configuration and Protected status verification | |
| 5 | T5-1~T5-4 | Overview information verification | |
| 5 | T5-5~T5-6 | Settings read-only field verification | |
| 5 | T5-7~T5-9 | RPC URL change and validation | |
| 6 | T6-1~T6-3 | Grafana metrics collection verification | |
| 6 | T6-4~T6-5 | Deployment log real-time refresh and download | |
| 6 | T6-6~T6-7 | Alert reception verification (Optional) | |
| 7 | T7-1~T7-3 | Snapshot creation | |
| 7 | T7-4~T7-6 | Backup restore | |
| 7 | T7-7~T7-9 | Storage attach | |
| 8 | T8-1~T8-2 | Integration component removal | |
| 8 | T8-3~T8-4 | Rollup deletion and AWS resource cleanup | |

**Total Test Items: 53** (Required: 46 / Optional: 7)

---

## Important Notes

- **Mainnet testing** consumes real ETH. Always use **Testnet** for testing.
- Deployment continues on the backend even if the browser is closed. Reopen the page to check progress.
- Integration components (Bridge, Explorer, etc.) can only be installed when the previous deployment is in **Deployed** status.
- The Backup tab is only enabled when the rollup status is **Deployed**.

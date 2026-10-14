# Session Initiation Protocol (SIP) Verification in Promela

Formal modeling and verification of the **Session Initiation Protocol (SIP)** over a reliable **Alternating Bit Protocol (ABP)** transport layer within a lossy network environment, implemented in **Promela** and verified using the **SPIN / iSpin** model checker.

---

## Overview

This project models the establishment, management, and termination of a VoIP call between two user agents (**Alice** and **Bob**) mediated by a **SIP Proxy Server**. 

To simulate a realistic and unreliable network environment, critical SIP messages (`INVITE`, `ACK`, `BYE`) are transmitted over an **Alternating Bit Protocol (ABP)** transport layer. The underlying network process introduces non-deterministic packet loss (for both data and acknowledgments) up to a bounded threshold (`MAX_NETWORK_DROPS = 3`) to verify protocol resilience without inducing infinite livelock from 100% disconnectivity.

---

## System Architecture

The system comprises **8 concurrent processes** (`proctype`) instantiated atomically:

### 1. Application Layer (SIP)
* **`Alice` (Caller):** Initiates the session (`INVITE`), handles provisional/final responses (`TRYING`, `RINGING`, `OK`, or error responses `NOT_FOUND`, `BUSY`, `REJECTED`), sends `ACK` to establish the session or acknowledge errors, and terminates active calls (`BYE`).
* **`Proxy` (SIP Server):** Receives incoming `INVITE` requests, replies with `TRYING`, non-deterministically resolves the callee's location (`NOT_FOUND` vs. forwarding to Bob), and routes responses back to Alice.
* **`Bob` (Callee):** Receives forwarded `INVITE` requests and non-deterministically accepts the call (`RINGING` -> `OK`), rejects it (`REJECTED`), or reports busy (`BUSY`).

### 2. Transport Layer (Alternating Bit Protocol - ABP)
* **`Alice_ABP_Transmitter` & `Proxy_ABP_Transmitter`:** Implement stop-and-wait ARQ with `timeout`-based retransmissions. `Alice_ABP_Transmitter` maintains independent sequence bits (`seq_proxy`, `seq_bob`) per peer to prevent state desynchronization across multiple connections.
* **`Proxy_ABP_Receiver` & `Bob_ABP_Receiver`:** Track expected sequence numbers (`exp_seq_alice`, `exp_seq_proxy`) to filter out duplicate packets from reaching the application layer while re-acknowledging (`ABP_ACK`) lost ACKs.

### 3. Network Infrastructure
* **`Network`:** Routes application and transport-layer packets between nodes and non-deterministically drops ABP data and `ABP_ACK` packets up to `MAX_NETWORK_DROPS`.

---

## Formal Verification (SPIN)

The model was exhaustively verified using **SPIN / iSpin** across both Safety and Liveness properties, yielding **0 errors**:

| Verification Mode | Property Checked | Mechanism Used | States Stored | Transitions | Errors |
| :--- | :--- | :--- | :---: | :---: | :---: |
| **Safety** | Deadlock Freedom & Valid End-States | `end_*` labels on daemon/service processes (`end_network`, `end_bob`, etc.) | 85,556 | 149,048 | **0** |
| **Safety** | State Transition Invariants | `assert(call_is_active == true)` before `BYE`; `assert(call_is_active == false)` on error paths | 85,556 | 149,048 | **0** |
| **Liveness** | Absence of Non-Progress Cycles (Livelocks) | `progress_*` labels on all valid call completion and error-handling states | 210,562 | 747,732 | **0** |

---

## How to Run

### Prerequisites
* [SPIN Model Checker](https://spinroot.com/)
* C Compiler (`gcc`)
* Optional: `iSpin` (Tcl/Tk GUI)

### 1. Run Simulation
```bash
spin sip.pml
```

### 2. Verify Safety (Deadlocks & Assertions)
```bash
spin -a sip.pml
gcc -DSAFETY -o pan pan.c
./pan
```

### 3. Verify Liveness (Non-Progress Cycles)
```bash
spin -a sip.pml
gcc -DNP -o pan pan.c
./pan -l
```

## Authors

This project was created by:

* **Orestis Zappas** - @OrestizZ (https://github.com/OrestizZ)

as a university assignment for the **Department of Informatics and Telecommunications (University of Peloponnese)**.

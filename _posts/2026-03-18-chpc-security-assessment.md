---
layout: post
title: "CHPC Security Assessment: Policies, Controls, and Gaps"
date: 2026-03-18 20:44 -0600
categories: [Security]
tags: [HPC, Security Policy, Software Supply Chain]
---

An assessment of the University of Utah's Center for High Performance Computing (CHPC) security posture, focusing on software package management, patching policies, and the Protected Environment for sensitive data.

## Useful Links

- [Module System](https://www.chpc.utah.edu/documentation/software/modules.php)
- [Getting Started](https://www.chpc.utah.edu/documentation/gettingstarted.php#Logging%20in)
- [Software Index](https://www.chpc.utah.edu/documentation/software/index.php)
- [Security Policy (1.6)](https://www.chpc.utah.edu/documentation/policies/1.6SecurityPolicy.php)
- [Protected Environment](https://www.chpc.utah.edu/resources/ProtectedEnvironment.php)
- [PE FAQ](https://www.chpc.utah.edu/documentation/pefaq.php)

## Software Package Management

### Can users customize and publish packages?

**No.** Module management is centrally controlled by CHPC staff. Users can search, load, and unload existing modules, but cannot create or publish new ones. To request new software, users must email `helpdesk@chpc.utah.edu` and a CHPC staff member will install it.

Users can customize their environment (`.bashrc`, `.tcshrc`, `.modulerc`) and control how modules are displayed/named, but this does not extend to creating or publishing modules.

### Available Software

CHPC categorizes available software as follows:

- **Scientific Applications**: Abaqus, AlphaFold/ColabFold, Amber, Ansys Fluent/Electronics Desktop, AutoDock, BLAST, Cambridge CSD, CCP4 Suite, Gaussian 16, GRACE, GROMACS, LAMMPS, Lumerical, MarvinSketch, NAMD, NWChem, ORCA, Quantum Espresso, VASP, VMD, WEKA, WRF
- **Access Utilities**: FastX, Duo MFA, Open OnDemand, RDP, screen, SSH, tmux, VPN
- **File Transfer and Management**: Aspera, Globus, Rclone
- **Scheduler (Slurm)**: Job scheduling, preemption, node sharing, PBS-to-Slurm conversion, DTN access
- **Software Installation**: Python environments (user install), Singularity/Apptainer, Spack
- **Programming Tools**: Compilers, data/math libraries, DDT/TotalView debugging, IDL, Intel oneAPI, Java, Jupyter, MPI libraries, MATLAB, Python, R, SAS, Stata, VS Code
- **ML/AI**: Deep learning, Generative AI
- **Environment Management**: Container-based virtualization, Modules, Advanced modules
- **Version Control**: Git, Subversion
- **Metrics**: XDMoD

## Software-Package-Related Security Policies

Policies extracted from across CHPC's documentation that directly govern how software is installed, updated, containerized, and controlled.

1. **Centralized software installation** — Users cannot install system-level software or publish modules. All module/package installation is performed by CHPC staff upon request. This eliminates user-introduced supply chain risk at the system level.

2. **User-level installation paths exist but are limited** — Users can install Python environments locally, use Spack, or build Apptainer/Singularity containers. These are the only sanctioned self-service software mechanisms.

3. **Container policy** — Docker is explicitly not recommended due to its root-level privilege model. CHPC mandates Apptainer/Singularity, which operates with "fakeroot" (user-level security, no actual root). This is a direct software-package security control in multi-user HPC.

4. **Patching cadence for system software** (Policy 1.6.2):
   - Vulnerability-driven SLAs based on NVD severity: 7 days (high) → 90 days (low).
   - Linux: daily auto-patching of security vulnerabilities (kernel excluded — manual review due to reboot impact).
   - HPC cluster hosts: patched quarterly during planned downtime. High-severity CVEs trigger risk evaluation and potential mini-downtimes.
   - Windows desktops: daily. Windows servers: weekly. PE Windows systems: regularly updated antivirus.
   - Network equipment: quarterly; critical patches within 7 days.
   - Institutional Security Office runs monthly Qualys scans for vulnerability detection.

5. **Only CHPC admins have root** (Policy 1.6.2) — On CHPC-administered hosts, only staff can install, patch, or configure software. Users have no privilege escalation path.

6. **Self-administered hosts** (Policy 1.6.2) — Users running their own machines on CHPC untrusted networks must: maintain patching, disable unnecessary services, configure firewalls, and implement failed-login blocking. CHPC does not manage software on these hosts.

7. **Software licensing compliance** — User agreements require compliance with all software licensing restrictions. This is a legal/policy control, not a technical one.

8. **PE software updates** — Protected Environment Linux hosts receive automatic monthly updates via Red Hat Network. Windows systems use Microsoft Update with regularly updated antivirus.

### Notable Gaps

CHPC's policies do not explicitly address:
- Integrity verification of user-installed packages (e.g., pip/conda checksum validation, signed packages).
- Scanning of user-built containers for vulnerabilities before deployment.
- Software bill of materials (SBOM) or dependency auditing.
- Restrictions on which package registries (PyPI, conda-forge, etc.) users can pull from.
- Runtime isolation or sandboxing of user-installed software beyond the container/fakeroot model.

## Security Policies

For full details, see the [CHPC Security Policy (1.6)](https://www.chpc.utah.edu/documentation/policies/1.6SecurityPolicy.php) and the [Protected Environment documentation](https://www.chpc.utah.edu/resources/ProtectedEnvironment.php).

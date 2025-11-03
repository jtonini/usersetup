# Usersetup - Enhanced Edition

**Original:** [georgeflanagin/usersetup](https://github.com/georgeflanagin/usersetup)  
**Fork maintainer:** [University of Richmond/João Tonini]

This is an enhanced fork of the original usersetup tool with additional enterprise features for user lifecycle management.

## What's New in This Fork?

### 🆕 Major Enhancements

1. **Automatic 'users' Group Membership**
   - All new users automatically added to 'users' group
   - Eliminates manual post-creation steps

2. **Time-Limited Guest Accounts**
   - Set expiration dates during account creation
   - Perfect for visitors, contractors, temporary staff
   - Accounts expire automatically without manual intervention

3. **Safe User Deletion**
   - Complete cleanup of user data
   - Automatic backup of home directory
   - Process termination and resource cleanup
   - Synchronization across compute nodes

4. **Account Management Commands**
   - List all users with expiration dates
   - Modify expiration dates for existing accounts
   - Convert temporary to permanent accounts

### Bug Fixes

- Fixed negation syntax in `userexists` check
- Fixed missing `echo` statement
- Improved error handling
- Added cleanup of temporary files

## Installation

### Fork and Clone

```bash
git clone https://github.com/jtonini/usersetup.git
cd usersetup
source usersetup.sh
```

### Or Download Directly

```bash
wget https://raw.githubusercontent.com/jtonini/usersetup/main/usersetup.sh
source usersetup.sh
```

## Quick Start

### 1. Choose Target Host

```bash
choosehost arachne
```

### 2. Create Users

**Permanent user:**
```bash
usersetup fred fred.pub.key
```

**Temporary user (expires in 90 days):**
```bash
usersetup fred fred.pub.key 90
```

### 3. Manage Users

**List all users:**
```bash
listusers
```

**Extend expiration:**
```bash
userexpiry fred 30  # Add 30 more days
```

**Make permanent:**
```bash
userexpiry fred never
```

**Delete user:**
```bash
userdelete fred
```

## Complete Command Reference

### Setup Commands

#### `choosehost {hostname}`
Set the target computer for user operations.

```bash
choosehost arachne
```

### User Creation

#### `usersetup {netid} [keyfile] [expiry_days]`
Create a new user account with optional expiration.

**Parameters:**
- `netid` - Username to create (required)
- `keyfile` - SSH public key file (optional, defaults to `netid.keys`)
- `expiry_days` - Days until account expires (optional, for guest accounts)

**Examples:**
```bash
# Permanent faculty/staff account
usersetup fred fred.pub.key

# Keyfile in current directory matching username
usersetup fred  # Looks for bob.keys # note: double check if it is looking for netid*key*

# Guest account (expires in 60 days)
usersetup fred fred.pub.key 60
```

**What it does:**
- Creates user account on target host
- Sets up SSH directory and authorized_keys
- Adds to DEFAULT_GROUP
- **Adds to 'users' group** (if exists)
- Generates ed25519 key pair
- Sets account expiration (if specified)
- Syncs to compute nodes

### User Deletion

#### `userdelete {netid} [--force]`
Safely delete a user account with complete cleanup.

**Parameters:**
- `netid` - Username to delete (required)
- `--force` - Skip confirmation prompt (optional)

**Examples:**
```bash
# Interactive deletion (asks for confirmation)
userdelete fred

# Force deletion (no confirmation)
userdelete fred --force
```

**What it does:**
- Prompts for confirmation (unless --force)
- Kills all user processes (graceful TERM, then KILL)
- **Creates timestamped backup** of home directory
- Removes user account
- Removes home directory
- Removes mail spool
- Removes temporary files
- Removes cron jobs
- Syncs deletion to compute nodes

**Backup location:** `/root/deleted_users/{username}_{timestamp}.tar.gz`

### Account Management

#### `listusers`
Display all users with their groups and expiration dates.

```bash
listusers
```

**Output:**
```
Username        UID     Groups                          Expiration
--------------------------------------------------------------------------------
fred            1001    users,staff,developers          never
bob             1002    users,admin                     never
guest01         1003    users                          Dec 31 2025
visitor         1004    users                          Jan 15 2026
```

#### `userexpiry {netid} {days|never}`
Modify account expiration for existing users.

**Parameters:**
- `netid` - Username (required)
- `days` - Days from today, or "never" for permanent

**Examples:**
```bash
# Extend guest account 30 days from today
userexpiry fred 30

# Remove expiration (make permanent)
userexpiry fred never

# Expire immediately
userexpiry fred 0
```

### Utility Commands

#### `userexists {username}`
Check if a user exists (local or LDAP).

```bash
userexists fred
```

#### `groupexists {groupname}`
Check if a group exists (local or remote).

```bash
groupexists users
```

#### `adduserkey {user} {keyfile}`
Add additional SSH keys to existing user.

```bash
adduserkey fred fred_laptop.pub
```

#### `usersetup_help`
Display comprehensive help and examples.

```bash
usersetup_help
```

### User Departure

```bash
source usersetup.sh
choosehost arachne

# Delete with confirmation
userdelete departing_user

# Verify deletion
listusers | grep departing_user

# Backup is in: /root/deleted_users/departing_user_*.tar.gz
```

### Monthly Audit

```bash
source usersetup.sh
choosehost arachne

# Review all users
listusers > user_audit_$(date +%Y%m%d).txt

# Check for accounts expiring soon
listusers | grep "2025-12"

# Extend if needed
userexpiry guest01 30
```

## Requirements

- Root access to target systems via SSH
- SSH key-based authentication configured
- Bash shell (Linux/Unix)
- Target system requirements:
  - `useradd`, `userdel`, `usermod` commands
  - `chage` command (for account expiration)
  - `getent` command
  - Optional: `users` group (created if missing)

## System Compatibility

Tested on:
- Ubuntu 20.04, 22.04, 24.04
- Debian 10, 11, 12
- CentOS 7, 8
- Rocky Linux 8, 9
- RHEL 7, 8, 9

## Architecture

```
┌─────────────────┐
│  Administrator  │
│    Workstation  │
└────────┬────────┘
         │ SSH (as root)
         ▼
┌─────────────────┐
│   Target Host   │
│  (User Master)  │
└────────┬────────┘
         │ sync_nodes.sh
         ▼
┌─────────────────┐
│  Compute Nodes  │
│  (1, 2, 3, ...) │
└─────────────────┘
```

## Files and Locations

### On Administrator's Workstation
- `usersetup.sh` - Main script (source this)
- `{username}.keys` - Public SSH keys
- `/tmp/{hostname}.userdefaults.txt` - Temporary files

### On Target Host
- `/home/{username}/` - User home directories
- `/home/{username}/.ssh/` - SSH configuration
- `/root/deleted_users/` - Backup of deleted users
- `sync_nodes.sh` - Node synchronization script (if exists)

## Configuration

### Default Group Detection

The script automatically detects the default group from the target system:

```bash
ssh "root@$USER_HOST" "useradd -D"
```

### Users Group

The script checks for and adds users to the 'users' group if it exists:

```bash
if getent group users > /dev/null 2>&1; then
    usermod -aG users "$username"
fi
```

If the 'users' group doesn't exist on your system, create it:

```bash
ssh root@targethost "groupadd users"
```

## Security Considerations

### Backup Retention

Deleted user backups are stored indefinitely in `/root/deleted_users/`.

**Recommended cleanup policy:**
```bash
# Delete backups older than 90 days
find /root/deleted_users -mtime +90 -delete
```

### Permissions

- Deletion script requires root access
- Backups stored in `/root/` (root-only access)
- SSH keys properly secured (600 for private, 644 for public)
- Home directories default to 2755 (SGID for group)

### Process Termination

User deletion follows graceful termination:
1. SIGTERM (graceful shutdown)
2. 2-second grace period
3. SIGKILL (force kill if needed)

### Audit Trail

Consider logging all operations:
```bash
# Add to your .bashrc
alias usersetup='usersetup 2>&1 | tee -a /var/log/usersetup.log'
alias userdelete='userdelete 2>&1 | tee -a /var/log/usersetup.log'
```

## Troubleshooting

### 'users' group not found

**Symptom:** Warning message about 'users' group
**Solution:** Create the group:
```bash
ssh root@targethost "groupadd users"
```

### User deletion fails

**Symptom:** Processes still running after deletion
**Diagnosis:**
```bash
ssh root@targethost "ps -u username"
```
**Solution:**
```bash
ssh root@targethost "pkill -9 -u username"
userdelete username --force
```

### Account not expiring

**Symptom:** User can still login after expiration date
**Diagnosis:**
```bash
ssh root@targethost "chage -l username"
```
**Solution:**
```bash
userexpiry username 0  # Expire immediately
```

### Backup directory full

**Symptom:** No space for backups
**Solution:**
```bash
# Check space
ssh root@targethost "df -h /root"

# Clean old backups
ssh root@targethost "find /root/deleted_users -mtime +90 -delete"
```

**Key additions:**
- Automatic 'users' group membership
- Time-limited accounts with expiration
- Safe user deletion with backup
- User listing and management commands
- Bug fixes and improved error handling
- Comprehensive help system

## License

Same as original usersetup project.

## Credits

**Original author:** George Flanagin  
**Original repository:** https://github.com/georgeflanagin/usersetup

**Enhancements:** [João Tonini/University of Richmond]

## Support

For issues specific to this fork:
- Open an issue on GitHub
- Include: command used, expected vs actual behavior, system info

For issues with original functionality:
- See original repository

## Changelog

### Version 2.0 (Enhanced Fork)
- Added automatic 'users' group membership
- Added time-limited account support
- Added `userdelete` command with backup
- Added `listusers` command
- Added `userexpiry` command
- Added `usersetup_help` command
- Fixed syntax errors in `userexists` check
- Fixed missing `echo` statement
- Improved error handling
- Added cleanup of temporary files

### Version 1.0 (Original)
- Initial release by George Flanagin
- User creation and SSH key management
- See original repository for details

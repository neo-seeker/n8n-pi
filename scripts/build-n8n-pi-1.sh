#!/bin/bash
logfile=/var/log/n8n-pi.log
sudo touch $logfile
sudo chmod 777 $logfile

# Deals with errors
error_exit() {
    echo "${1:-"Unknown Error"}" 1>&2
    echo "Last 10 entries by this script:"
    tail $logfile
    echo "Full log details are recorded in $logfile"
    echo
    echo "You can rerun this script by using the command:"
    echo "wget --no-cache -O - https://raw.githubusercontent.com/neo-seeker/n8n-pi/master/scripts/build-n8n-pi-1.sh | bash"
    exit 1
}

# Create log headings
log_heading() {
    length=${#1}
    length=$(expr $length + 8)
    printf '%*s' $length | tr ' ' '*' >>$logfile
    echo >>$logfile
    echo "*** $1 ***" >>$logfile
    printf '%*s' $length | tr ' ' '*' >>$logfile
    echo >>$logfile
    echo -n "$1..."
}

# Use sudo if not root
SUDO=''
if [[ $EUID -ne 0 ]]; then
    SUDO='sudo'
fi

clear

# Introduction message
message=$'This script is designed to build a new n8n-pi from a base Raspbian Lite installation.\n\nThis is the first of two scripts that need to be run.\n\nIt will perform the following actions:\n    1. Update Raspian Lite to the latest software\n    2. Install dependencies\n    3. Rename the server\n    4. Add the n8n user\n    5. Install base custom MOTD\n    6. Update hostname\n    7. Reboot'
whiptail --backtitle "n8n-pi Installer" --title "Welcome to the n8n-pi Installer" --msgbox "$message" 17 78

# Ask for permission to continue
if (whiptail --backtitle "n8n-pi Installer" --title "Continue with install?" --yesno "Do you wish to continue with the installation?" 8 78); then

    # Update package list
    log_heading "Updating package list"
    $SUDO apt update &>>$logfile || error_exit "$LINENO: Unable to update apt sources"
    echo "done!"

    # Upgrade packages
    log_heading "Upgrading packages (Please be patient, this may take a while)"
    $SUDO apt upgrade -y &>>$logfile || error_exit "$LINENO: Unable to upgrade packages"
    echo "done!"

    # Install dependencies
    log_heading "Installing dependencies"
    $SUDO apt install figlet jq build-essential -y &>>$logfile || error_exit "$LINENO: Unable to install dependencies"
    echo "done!"

    # Create the n8n user (if not already existing)
    log_heading "Creating n8n user"
    if id "n8n" &>/dev/null; then
        echo "User n8n already exists, skipping creation." >>$logfile
    else
        $SUDO adduser --disabled-password --gecos "" n8n &>>$logfile || error_exit "$LINENO: Unable to create n8n user"
    fi
    # Add n8n to sudo group
    $SUDO usermod -a -G sudo n8n &>>$logfile || error_exit "$LINENO: Unable to add n8n user to sudo group"
    echo 'n8n:n8n=gr8!' | $SUDO chpasswd &>>$logfile || error_exit "$LINENO: Unable to set n8n password"
    $SUDO cp /etc/sudoers /etc/sudoers.org &>>$logfile || error_exit "$LINENO: Unable to create backup of /etc/sudoers"
    echo 'n8n   ALL=(ALL) NOPASSWD:ALL' | $SUDO EDITOR='tee -a' visudo &>>$logfile || error_exit "$LINENO: Unable to remove n8n sudo password requirement"
    echo "done!"

    # Update MOTD (Message of the Day)
    log_heading "Updating MOTD (1 of 2)"
    $SUDO wget --no-cache -O /etc/update-motd.d/10-sysinfo https://raw.githubusercontent.com/neo-seeker/n8n-pi/master/motd/10-sysinfo &>>$logfile || error_exit "$LINENO: Unable to retrieve 10-sysinfo file"
    $SUDO chmod 755 /etc/update-motd.d/10-sysinfo &>>$logfile || error_exit "$LINENO: Unable to set 10-sysinfo permissions"
    $SUDO rm -f /etc/update-motd.d/10-uname &>>$logfile || error_exit "$LINENO: Unable to remove /etc/update-motd.d/10-uname"
    $SUDO truncate -s 0 /etc/motd &>>$logfile || error_exit "$LINENO: Unable to clear /etc/motd"
    $SUDO rm -f /etc/profile.d/sshpwd.sh &>>$logfile || error_exit "$LINENO: Unable to remove /etc/profile.d/sshpwd.sh"
    $SUDO rm -f /etc/profile.d/wifi-check.sh &>>$logfile || error_exit "$LINENO: Unable to remove /etc/profile.d/wifi-check.sh"
    $SUDO sed -i 's/#PrintLastLog yes/PrintLastLog no/g' /etc/ssh/sshd_config &>>$logfile || error_exit "$LINENO: Unable to disable last login message in /etc/ssh/sshd_config"
    echo "done!"

    # Reset hostname
    log_heading "Setting new hostname"
    newhostname=$(whiptail --backtitle "n8n-pi Installer" --inputbox "Please provide a new hostname:" 8 34 n8n-pi --title "New Hostname" 3>&1 1>&2 2>&3)
    echo $newhostname | $SUDO tee /etc/hostname  &>>$logfile || error_exit "$LINENO: Unable to set new hostname in /etc/hostname"
    $SUDO sed -i "s/raspberrypi/$newhostname/g" /etc/hosts &>>$logfile || error_exit "$LINENO: Unable to update /etc/hosts with new hostname"
    echo "done!"

    # Prepare for reboot: download build-n8n-pi-2.sh
    log_heading "Preparing for reboot"
    $SUDO wget --no-cache -O /home/n8n/build-n8n-pi-2.sh https://raw.githubusercontent.com/neo-seeker/n8n-pi/master/scripts/build-n8n-pi-2.sh &>>$logfile || error_exit "$LINENO: Unable to retrieve build-n8n-pi-2.sh"
    $SUDO chmod 755 /home/n8n/build-n8n-pi-2.sh &>>$logfile || error_exit "$LINENO: Unable to set permissions for build-n8n-pi-2.sh"
    $SUDO chown n8n:n8n /home/n8n/build-n8n-pi-2.sh &>>$logfile || error_exit "$LINENO: Unable to set ownership for build-n8n-pi-2.sh"

    # Ensure /home/n8n/.bashrc exists; create it if it doesn't.
    if [ ! -f /home/n8n/.bashrc ]; then
        echo "/home/n8n/.bashrc not found. Creating a new .bashrc file." >>$logfile
        if [ -z "$SUDO" ]; then
            touch /home/n8n/.bashrc || error_exit "$LINENO: Unable to create /home/n8n/.bashrc"
            chown n8n:n8n /home/n8n/.bashrc || error_exit "$LINENO: Unable to set ownership for /home/n8n/.bashrc"
        else
            $SUDO -u n8n touch /home/n8n/.bashrc || error_exit "$LINENO: Unable to create /home/n8n/.bashrc"
        fi
    fi

    # Backup .bashrc (if exists, even if it was just created, it will be empty)
    if [ -f /home/n8n/.bashrc ]; then
        $SUDO cp /home/n8n/.bashrc /home/n8n/.bashrc-org &>>$logfile || error_exit "$LINENO: Unable to backup /home/n8n/.bashrc"
        $SUDO chown n8n:n8n /home/n8n/.bashrc-org &>>$logfile || error_exit "$LINENO: Unable to set ownership for /home/n8n/.bashrc-org"
    else
        error_exit "$LINENO: /home/n8n/.bashrc not found after creation."
    fi

    # Append autorun entry
    echo '~/build-n8n-pi-2.sh' | $SUDO tee --append /home/n8n/.bashrc &>>$logfile || error_exit "$LINENO: Unable to update /home/n8n/.bashrc to autorun build-n8n-pi-2.sh"
    echo "done!"

    # Final message and instructions
    message=$'The first phase of the installation has finished. We must now reboot the system in order for some changes to take effect and so you can log in as the new n8n user to continue the installation.\n\nWhen the system comes back online, please log in with the following credentials:\n    • Username: n8n\n    • Password: n8n=gr8!\n\nPro Tip: Write down that username and password so you have it handy.'
    whiptail --backtitle "n8n-pi Installer" --title "Time to Reboot" --msgbox "$message" 17 78
    log_heading "Reboot"
    $SUDO reboot &>>$logfile || error_exit "$LINENO: Unable to reboot"

else 
    error_exit "$LINENO: Installation cancelled"
fi

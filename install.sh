#!/bin/bash
# ============================================================================
# PSWebHost Installation Script for Linux/macOS
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo ""
echo "========================================================================================================"
echo "  PSWebHost Installation"
echo "========================================================================================================"
echo ""

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check if PowerShell 7+ is installed
if command -v pwsh &> /dev/null; then
    PWSH_VERSION=$(pwsh -NoProfile -Command '$PSVersionTable.PSVersion.Major')
    if [ "$PWSH_VERSION" -ge 7 ]; then
        echo -e "${GREEN}[OK]${NC} PowerShell 7+ detected (version $PWSH_VERSION)"
        RUN_SETUP=true
    else
        echo -e "${RED}[!]${NC} PowerShell $PWSH_VERSION detected, but version 7+ is required"
        RUN_SETUP=false
    fi
else
    echo -e "${YELLOW}[!]${NC} PowerShell 7 is not installed"
    RUN_SETUP=false
fi

# If PowerShell 7+ is not installed, offer to install it
if [ "$RUN_SETUP" = false ]; then
    echo ""
    echo "PSWebHost requires PowerShell 7 or later to run."
    echo ""

    # Detect OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS=$ID
            VER=$VERSION_ID
        fi

        echo "Detected OS: $OS"
        echo ""

        if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
            echo "To install PowerShell 7 on Ubuntu/Debian:"
            echo ""
            echo -e "${CYAN}  sudo apt-get update"
            echo "  sudo apt-get install -y wget apt-transport-https software-properties-common"
            echo "  wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb"
            echo "  sudo dpkg -i packages-microsoft-prod.deb"
            echo "  sudo apt-get update"
            echo -e "  sudo apt-get install -y powershell${NC}"
            echo ""

            read -p "Would you like to install PowerShell 7 now? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                sudo apt-get update
                sudo apt-get install -y wget apt-transport-https software-properties-common
                wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb
                sudo dpkg -i packages-microsoft-prod.deb
                rm packages-microsoft-prod.deb
                sudo apt-get update
                sudo apt-get install -y powershell

                if command -v pwsh &> /dev/null; then
                    echo -e "${GREEN}[OK]${NC} PowerShell 7 installed successfully!"
                    RUN_SETUP=true
                else
                    echo -e "${RED}[ERROR]${NC} PowerShell installation failed."
                    exit 1
                fi
            else
                echo "Installation cancelled."
                exit 1
            fi

        elif [ "$OS" = "fedora" ] || [ "$OS" = "rhel" ] || [ "$OS" = "centos" ]; then
            echo "To install PowerShell 7 on RHEL/CentOS/Fedora:"
            echo ""
            echo -e "${CYAN}  sudo dnf install -y powershell${NC}"
            echo ""

            read -p "Would you like to install PowerShell 7 now? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                sudo dnf install -y powershell

                if command -v pwsh &> /dev/null; then
                    echo -e "${GREEN}[OK]${NC} PowerShell 7 installed successfully!"
                    RUN_SETUP=true
                else
                    echo -e "${RED}[ERROR]${NC} PowerShell installation failed."
                    exit 1
                fi
            else
                echo "Installation cancelled."
                exit 1
            fi

        elif [ "$OS" = "arch" ]; then
            echo "To install PowerShell 7 on Arch Linux:"
            echo ""
            echo -e "${CYAN}  yay -S powershell-bin${NC}"
            echo ""
            echo "Please install PowerShell manually and run this script again."
            exit 1
        else
            echo "Unsupported Linux distribution: $OS"
            echo "Please install PowerShell 7 manually:"
            echo "  https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell"
            exit 1
        fi

    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        echo "Detected OS: macOS"
        echo ""

        if command -v brew &> /dev/null; then
            echo "To install PowerShell 7 on macOS:"
            echo ""
            echo -e "${CYAN}  brew install --cask powershell${NC}"
            echo ""

            read -p "Would you like to install PowerShell 7 now using Homebrew? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                brew install --cask powershell

                if command -v pwsh &> /dev/null; then
                    echo -e "${GREEN}[OK]${NC} PowerShell 7 installed successfully!"
                    RUN_SETUP=true
                else
                    echo -e "${RED}[ERROR]${NC} PowerShell installation failed."
                    exit 1
                fi
            else
                echo "Installation cancelled."
                exit 1
            fi
        else
            echo -e "${YELLOW}[!]${NC} Homebrew is not installed."
            echo ""
            echo "Please install Homebrew first:"
            echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            echo ""
            echo "Then install PowerShell:"
            echo "  brew install --cask powershell"
            exit 1
        fi
    else
        echo "Unsupported operating system: $OSTYPE"
        echo "Please install PowerShell 7 manually:"
        echo "  https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell"
        exit 1
    fi
fi

# Run setup if PowerShell is available
if [ "$RUN_SETUP" = true ]; then
    echo ""
    echo "========================================================================================================"
    echo "  Running PSWebHost Setup..."
    echo "========================================================================================================"
    echo ""

    pwsh -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/WebHost.ps1" -ShowVariables

    if [ $? -eq 0 ]; then
        echo ""
        echo "========================================================================================================"
        echo "  Installation Complete!"
        echo "========================================================================================================"
        echo ""
        echo "To start PSWebHost, run:"
        echo "  pwsh -File $SCRIPT_DIR/WebHost.ps1"
        echo ""
    else
        echo ""
        echo -e "${RED}[ERROR]${NC} Setup encountered errors. Please review the output above."
        echo ""
        exit 1
    fi
fi

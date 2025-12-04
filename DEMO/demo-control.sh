#!/bin/bash

# Unified Demo Application Control Script
# Manages all demo applications: Python Flask, .NET Core, Node.js Express, Java Tomcat, and PHP Drupal

set -e

# Application configurations
declare -A APPS
APPS[python]="python-flask:9090:/demos/flask-app:python3 app.py"
APPS[node]="node-express:3030:/demos/node-app:npm start"
APPS[netcore]="dotnet-core:8181:/demos/dotnet-app:dotnet run"
APPS[tomcat]="tomcat-java:8080:/demos/apache-tomcat-9.0.95/bin/startup.sh"
APPS[drupal]="drupal-php:7070:/demos/drupal-app:bash /demos/drupal-app/start.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to get app configuration
get_app_config() {
    local app=$1
    local config=${APPS[$app]}
    if [ -z "$config" ]; then
        print_status $RED "❌ Unknown application: $app"
        show_usage
        exit 1
    fi
    echo "$config"
}

# Function to parse app configuration
parse_config() {
    local config=$1
    local field=$2
    echo "$config" | cut -d: -f$field
}

# Function to get PID file path
get_pid_file() {
    local app=$1
    echo "/tmp/${app}-demo.pid"
}

# Function to get log file path
get_log_file() {
    local app=$1
    echo "/tmp/${app}-demo.log"
}

# Function to start an application
start_app() {
    local app=$1
    local config=$(get_app_config $app)
    local app_name=$(parse_config "$config" 1)
    local port=$(parse_config "$config" 2)
    local directory=$(parse_config "$config" 3)
    local command=$(parse_config "$config" 4)
    local pid_file=$(get_pid_file $app)
    local log_file=$(get_log_file $app)
    
    print_status $BLUE "🚀 Starting $app_name..."
    
    # Check if already running
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if ps -p $pid > /dev/null 2>&1; then
            print_status $YELLOW "⚠️ $app_name is already running (PID: $pid)"
            return 0
        else
            print_status $YELLOW "🧹 Removing stale PID file"
            rm -f "$pid_file"
        fi
    fi
    
    # Special handling for different app types
    case $app in
        python)
            cd "$directory"
            print_status $GREEN "📦 Setting up Python environment..."
            # Check if virtual environment exists
            if [ ! -d "/opt/flask-env" ]; then
                print_status $YELLOW "⚠️ Flask virtual environment not found, using system Python"
                nohup $command > "$log_file" 2>&1 &
            else
                nohup /opt/flask-env/bin/python app.py > "$log_file" 2>&1 &
            fi
            ;;
        node)
            cd "$directory"
            print_status $GREEN "📦 Installing Node.js dependencies..."
            npm install > /dev/null 2>&1
            nohup $command > "$log_file" 2>&1 &
            local npm_pid=$!
            # Wait a moment for node to start, then find the actual node process
            sleep 2
            local node_pid=$(pgrep -f "node.*app.js" | head -1)
            if [ ! -z "$node_pid" ]; then
                echo $node_pid > "$pid_file"
                app_pid=$node_pid
            else
                echo $npm_pid > "$pid_file"
                app_pid=$npm_pid
            fi
            ;;
        netcore)
            cd "$directory"
            print_status $GREEN "🔨 Building .NET Core application..."
            dotnet build > /dev/null 2>&1
            nohup $command --urls "http://0.0.0.0:$port" > "$log_file" 2>&1 &
            ;;
        tomcat)
            print_status $GREEN "☕ Starting Tomcat..."
            cd "$directory"
            # Stop first if running
            ./apache-tomcat-9.0.95/bin/shutdown.sh > /dev/null 2>&1 || true
            sleep 2
            nohup ./apache-tomcat-9.0.95/bin/startup.sh > "$log_file" 2>&1 &
            ;;
        drupal)
            print_status $GREEN "🐘 Starting Drupal with Apache..."
            cd "$directory"
            bash /demos/drupal-app/start.sh > "$log_file" 2>&1
            ;;
    esac
    
    # For non-node apps, capture the PID normally
    if [ "$app" != "node" ]; then
        local app_pid=$!
        echo $app_pid > "$pid_file"
    fi
    
    # Wait a moment and verify startup
    sleep 3
    
    # Special verification for Tomcat and Drupal since they have different startup patterns
    if [ "$app" = "tomcat" ]; then
        # For Tomcat, check if Tomcat process is running and port is active
        local tomcat_running=false
        local attempts=0
        while [ $attempts -lt 10 ]; do
            local java_pids=$(pgrep -f "java.*tomcat" 2>/dev/null || true)
            local port_pids=$(lsof -ti:$port 2>/dev/null || true)
            if [ ! -z "$java_pids" ] || [ ! -z "$port_pids" ]; then
                tomcat_running=true
                break
            fi
            sleep 1
            attempts=$((attempts + 1))
        done
        
        if [ "$tomcat_running" = true ]; then
            print_status $GREEN "✅ $app_name started successfully"
            print_status $BLUE "🌐 Access at: http://localhost:$port/contrast-demo"
        else
            print_status $RED "❌ Failed to start $app_name"
            rm -f "$pid_file"
            return 1
        fi
    elif [ "$app" = "drupal" ]; then
        # For Drupal, check if Apache is running on the port
        local drupal_running=false
        local attempts=0
        while [ $attempts -lt 10 ]; do
            local apache_pids=$(pgrep -f "apache2" 2>/dev/null || true)
            local port_pids=$(lsof -ti:$port 2>/dev/null || true)
            if [ ! -z "$apache_pids" ] || [ ! -z "$port_pids" ]; then
                drupal_running=true
                break
            fi
            sleep 1
            attempts=$((attempts + 1))
        done
        
        if [ "$drupal_running" = true ]; then
            print_status $GREEN "✅ $app_name started successfully"
            print_status $BLUE "🌐 Access at: http://localhost:$port"
        else
            print_status $RED "❌ Failed to start $app_name"
            return 1
        fi
    else
        # For other apps, check the captured PID
        if ps -p $app_pid > /dev/null 2>&1; then
            print_status $GREEN "✅ $app_name started successfully (PID: $app_pid)"
            if [ "$app" = "tomcat" ]; then
                print_status $BLUE "🌐 Access at: http://localhost:$port/contrast-demo"
            else
                print_status $BLUE "🌐 Access at: http://localhost:$port"
            fi
        else
            print_status $RED "❌ Failed to start $app_name"
            rm -f "$pid_file"
            return 1
        fi
    fi
}

# Function to stop an application
stop_app() {
    local app=$1
    local config=$(get_app_config $app)
    local app_name=$(parse_config "$config" 1)
    local port=$(parse_config "$config" 2)
    local pid_file=$(get_pid_file $app)
    
    print_status $BLUE "🛑 Stopping $app_name..."
    
    # Special handling for different app types
    case $app in
        node)
            # For Node.js, kill all node processes on the port and by name
            local port_pids=$(lsof -ti:$port 2>/dev/null || true)
            local node_pids=$(pgrep -f "node.*app.js" 2>/dev/null || true)
            local npm_pids=$(pgrep -f "npm.*start" 2>/dev/null || true)
            
            # Kill by port first
            if [ ! -z "$port_pids" ]; then
                print_status $YELLOW "🔍 Killing processes on port $port: $port_pids"
                echo "$port_pids" | xargs kill 2>/dev/null || true
                sleep 1
                # Force kill if still running
                echo "$port_pids" | xargs kill -9 2>/dev/null || true
            fi
            
            # Kill node processes
            if [ ! -z "$node_pids" ]; then
                print_status $YELLOW "� Killing node processes: $node_pids"
                echo "$node_pids" | xargs kill 2>/dev/null || true
                sleep 1
                echo "$node_pids" | xargs kill -9 2>/dev/null || true
            fi
            
            # Kill npm processes
            if [ ! -z "$npm_pids" ]; then
                print_status $YELLOW "🔍 Killing npm processes: $npm_pids"
                echo "$npm_pids" | xargs kill 2>/dev/null || true
                sleep 1
                echo "$npm_pids" | xargs kill -9 2>/dev/null || true
            fi
            ;;
        tomcat)
            # Special handling for Tomcat
            cd "$directory"
            ./apache-tomcat-9.0.95/bin/shutdown.sh > /dev/null 2>&1 || true
            sleep 2
            # Also kill by port if shutdown script didn't work
            local port_pids=$(lsof -ti:$port 2>/dev/null || true)
            if [ ! -z "$port_pids" ]; then
                print_status $YELLOW "🔍 Force killing Tomcat processes on port $port"
                echo "$port_pids" | xargs kill -9 2>/dev/null || true
            fi
            ;;
        drupal)
            # Special handling for Drupal/Apache
            bash /demos/drupal-app/stop.sh > /dev/null 2>&1 || true
            sleep 2
            # Also kill by port if stop script didn't work
            local port_pids=$(lsof -ti:$port 2>/dev/null || true)
            if [ ! -z "$port_pids" ]; then
                print_status $YELLOW "🔍 Force killing Apache processes on port $port"
                echo "$port_pids" | xargs kill -9 2>/dev/null || true
            fi
            ;;
        *)
            # Default handling for Python and .NET Core
            local killed_something=false
            
            # Try PID file first
            if [ -f "$pid_file" ]; then
                local pid=$(cat "$pid_file")
                if ps -p $pid > /dev/null 2>&1; then
                    kill $pid
                    sleep 2
                    if ps -p $pid > /dev/null 2>&1; then
                        print_status $YELLOW "🔨 Force killing $app_name..."
                        kill -9 $pid
                    fi
                    killed_something=true
                fi
                rm -f "$pid_file"
            fi
            
            # Also try to kill by port
            local port_pids=$(lsof -ti:$port 2>/dev/null || true)
            if [ ! -z "$port_pids" ]; then
                print_status $YELLOW "🔍 Found processes on port $port, killing..."
                echo "$port_pids" | xargs kill 2>/dev/null || true
                sleep 1
                echo "$port_pids" | xargs kill -9 2>/dev/null || true
                killed_something=true
            fi
            
            if [ "$killed_something" = false ]; then
                print_status $YELLOW "⚠️ $app_name was not running"
            fi
            ;;
    esac
    
    # Clean up PID file
    rm -f "$pid_file"
    
    # Verify that the port is now free
    sleep 1
    local remaining_pids=$(lsof -ti:$port 2>/dev/null || true)
    if [ -z "$remaining_pids" ]; then
        print_status $GREEN "✅ $app_name stopped successfully"
    else
        print_status $RED "⚠️ Some processes may still be running on port $port"
    fi
}

# Function to restart an application
restart_app() {
    local app=$1
    local config=$(get_app_config $app)
    local app_name=$(parse_config "$config" 1)
    
    print_status $BLUE "🔄 Restarting $app_name..."
    stop_app $app
    sleep 2
    start_app $app
}

# Function to show application status
status_app() {
    local app=$1
    local config=$(get_app_config $app)
    local app_name=$(parse_config "$config" 1)
    local port=$(parse_config "$config" 2)
    local directory=$(parse_config "$config" 3)
    local pid_file=$(get_pid_file $app)
    
    # Debug mode - set DEBUG=1 to see detailed detection info
    local debug_mode=${DEBUG:-0}
    
    print_status $BLUE "📊 $app_name Status:"
    
    # Check for actual running processes first
    local is_running=false
    local actual_pids=""
    
    case $app in
        node)
            # Check for node processes - be more specific
            local node_pids=$(pgrep -f "node.*app\.js" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
            local npm_pids=$(pgrep -f "npm.*start" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
            # Try multiple methods to detect port usage
            local port_pids_lsof=$(lsof -ti:$port 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
            local port_pids_netstat=$(netstat -tlpn 2>/dev/null | grep ":$port " | awk '{print $7}' | cut -d'/' -f1 | tr '\n' ' ' | sed 's/[[:space:]]*$//')
            local port_pids="${port_pids_lsof}${port_pids_netstat}"
            
            if [ "$debug_mode" = "1" ]; then
                echo "DEBUG: node_pids='$node_pids' (length: ${#node_pids})"
                echo "DEBUG: npm_pids='$npm_pids' (length: ${#npm_pids})"
                echo "DEBUG: port_pids_lsof='$port_pids_lsof'"
                echo "DEBUG: port_pids_netstat='$port_pids_netstat'"
                echo "DEBUG: combined port_pids='$port_pids'"
            fi
            
            # Only consider running if we have actual processes
            if [ -n "$node_pids" ] || [ -n "$port_pids" ]; then
                is_running=true
                actual_pids="Node: ${node_pids:-none}, NPM: ${npm_pids:-none}, Port: ${port_pids:-none}"
            fi
            ;;
        python)
            # Check for python processes - more specific pattern
            local python_pids=$(pgrep -f "python.*app\.py" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
            # Try multiple methods to detect port usage
            local port_pids_lsof=$(lsof -ti:$port 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
            local port_pids_netstat=$(netstat -tlpn 2>/dev/null | grep ":$port " | awk '{print $7}' | cut -d'/' -f1 | tr '\n' ' ' | sed 's/[[:space:]]*$//')
            local port_pids="${port_pids_lsof}${port_pids_netstat}"
            
            if [ "$debug_mode" = "1" ]; then
                echo "DEBUG: python_pids='$python_pids' (length: ${#python_pids})"
                echo "DEBUG: port_pids_lsof='$port_pids_lsof'"
                echo "DEBUG: port_pids_netstat='$port_pids_netstat'"
                echo "DEBUG: combined port_pids='$port_pids'"
                echo "DEBUG: Port check command: lsof -ti:$port"
                lsof -i:$port 2>/dev/null || echo "DEBUG: No lsof output for port $port"
                netstat -tlpn 2>/dev/null | grep ":$port " || echo "DEBUG: No netstat output for port $port"
            fi
            
            if [ -n "$python_pids" ] || [ -n "$port_pids" ]; then
                is_running=true
                actual_pids="Python: ${python_pids:-none}, Port: ${port_pids:-none}"
            fi
            ;;
        netcore)
            # Check for dotnet processes - more specific pattern
            local dotnet_pids=$(pgrep -f "dotnet.*run" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
            # Try multiple methods to detect port usage
            local port_pids_lsof=$(lsof -ti:$port 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
            local port_pids_netstat=$(netstat -tlpn 2>/dev/null | grep ":$port " | awk '{print $7}' | cut -d'/' -f1 | tr '\n' ' ' | sed 's/[[:space:]]*$//')
            local port_pids="${port_pids_lsof}${port_pids_netstat}"
            
            if [ "$debug_mode" = "1" ]; then
                echo "DEBUG: dotnet_pids='$dotnet_pids' (length: ${#dotnet_pids})"
                echo "DEBUG: port_pids_lsof='$port_pids_lsof'"
                echo "DEBUG: port_pids_netstat='$port_pids_netstat'"
                echo "DEBUG: combined port_pids='$port_pids'"
                echo "DEBUG: Port check command: lsof -ti:$port"
                lsof -i:$port 2>/dev/null || echo "DEBUG: No lsof output for port $port"
                netstat -tlpn 2>/dev/null | grep ":$port " || echo "DEBUG: No netstat output for port $port"
            fi
            
            if [ -n "$dotnet_pids" ] || [ -n "$port_pids" ]; then
                is_running=true
                actual_pids="DotNet: ${dotnet_pids:-none}, Port: ${port_pids:-none}"
            fi
            ;;
        tomcat)
            # Check for tomcat processes
            local java_pids=$(pgrep -f "java.*tomcat" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
            # Try multiple methods to detect port usage
            local port_pids_lsof=$(lsof -ti:$port 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
            local port_pids_netstat=$(netstat -tlpn 2>/dev/null | grep ":$port " | awk '{print $7}' | cut -d'/' -f1 | tr '\n' ' ' | sed 's/[[:space:]]*$//')
            local port_pids="${port_pids_lsof}${port_pids_netstat}"
            
            if [ "$debug_mode" = "1" ]; then
                echo "DEBUG: java_pids='$java_pids' (length: ${#java_pids})"
                echo "DEBUG: port_pids_lsof='$port_pids_lsof'"
                echo "DEBUG: port_pids_netstat='$port_pids_netstat'"
                echo "DEBUG: combined port_pids='$port_pids'"
            fi
            
            if [ -n "$java_pids" ] || [ -n "$port_pids" ]; then
                is_running=true
                actual_pids="Tomcat: ${java_pids:-none}, Port: ${port_pids:-none}"
            fi
            ;;
    esac
    
    # Check PID file status
    local pid_file_status=""
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if ps -p $pid > /dev/null 2>&1; then
            pid_file_status="Valid PID file (PID: $pid)"
        else
            pid_file_status="Stale PID file (PID: $pid - not running)"
            rm -f "$pid_file"
        fi
    else
        pid_file_status="No PID file"
    fi
    
    # Report status
    if [ "$is_running" = true ]; then
        print_status $GREEN "✅ Status: Running"
        if [ "$app" = "tomcat" ]; then
            print_status $BLUE "🌐 URL: http://localhost:$port/contrast-demo"
        else
            print_status $BLUE "🌐 URL: http://localhost:$port"
        fi
        print_status $BLUE "📂 Directory: $directory"
        print_status $BLUE "🔍 PIDs: $actual_pids"
        print_status $BLUE "📄 PID File: $pid_file_status"
    else
        print_status $RED "❌ Status: Not running"
        print_status $BLUE "📄 PID File: $pid_file_status"
    fi
    
    # Additional port check with details - but be smarter about inconsistencies
    local all_port_pids=$(lsof -ti:$port 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    
    if [ "$debug_mode" = "1" ]; then
        echo "DEBUG: Final port check: all_port_pids='$all_port_pids'"
        echo "DEBUG: is_running='$is_running'"
    fi
    
    if [ -n "$all_port_pids" ]; then
        if [ "$is_running" = false ]; then
            print_status $YELLOW "⚠️ Inconsistency: Port $port is in use by PIDs: $all_port_pids (but app not detected as running)"
            # Show what processes are using the port
            print_status $BLUE "Port details:"
            lsof -i:$port 2>/dev/null | head -5 || true
        fi
    elif [ "$is_running" = true ]; then
        # Only show inconsistency if we detected processes but can't find port usage
        # AND the processes should be using the port (not just build processes, etc.)
        case $app in
            python|node|netcore|tomcat)
                # These apps should definitely be using their ports if running
                if [[ "$actual_pids" == *"Port: none"* ]]; then
                    print_status $YELLOW "⚠️ Note: App processes detected but port $port not showing as in use (may be normal during startup)"
                fi
                ;;
        esac
    fi
}

# Function to show logs
show_logs() {
    local app=$1
    local config=$(get_app_config $app)
    local app_name=$(parse_config "$config" 1)
    local log_file=$(get_log_file $app)
    
    if [ -f "$log_file" ]; then
        print_status $BLUE "📄 Showing last 50 lines of $app_name logs:"
        echo "----------------------------------------"
        tail -50 "$log_file"
        echo "----------------------------------------"
    else
        print_status $RED "❌ Log file not found: $log_file"
    fi
}

# Function to show status of all applications
status_all() {
    print_status $BLUE "📊 All Demo Applications Status:"
    echo "======================================="
    for app in python node netcore tomcat; do
        status_app $app
        echo "---------------------------------------"
    done
}

# Function to start all applications
start_all() {
    print_status $BLUE "🚀 Starting all demo applications..."
    for app in python node netcore tomcat; do
        start_app $app
        echo "---------------------------------------"
    done
}

# Function to stop all applications
stop_all() {
    print_status $BLUE "🛑 Stopping all demo applications..."
    for app in python node netcore tomcat; do
        stop_app $app
    done
}

# Function to show usage
show_usage() {
    echo "Usage: $0 <application> <command>"
    echo "       $0 all <command>"
    echo ""
    echo "Applications:"
    echo "  python   - Python Flask application (port 9090)"
    echo "  node     - Node.js Express application (port 3030)"
    echo "  netcore  - .NET Core application (port 8181)"
    echo "  tomcat   - Apache Tomcat application (port 8080)"
    echo "  drupal   - PHP Drupal 11 application (port 7070)"
    echo "  all      - All applications"
    echo ""
    echo "Commands:"
    echo "  start    - Start the application(s)"
    echo "  stop     - Stop the application(s)"
    echo "  restart  - Restart the application(s)"
    echo "  status   - Show application status"
    echo "  logs     - Show application logs (not available for 'all')"
    echo ""
    echo "Examples:"
    echo "  $0 node start           # Start Node.js application"
    echo "  $0 python stop          # Stop Python application"
    echo "  $0 netcore restart      # Restart .NET Core application"
    echo "  $0 tomcat status        # Show Tomcat application status"
    echo "  $0 drupal start         # Start Drupal application"
    echo "  $0 node logs            # Show Node.js application logs"
    echo "  $0 all start            # Start all applications"
    echo "  $0 all status           # Show status of all applications"
    echo ""
    echo "Application URLs:"
    echo "  Python:   http://localhost:9090"
    echo "  Node.js:  http://localhost:3030"
    echo "  .NET:     http://localhost:8181"
    echo "  Tomcat:   http://localhost:8080/contrast-demo"
    echo "  Drupal:   http://localhost:7070/contrast-demo"
}

# Main script logic
if [ $# -lt 2 ]; then
    show_usage
    exit 1
fi

APP=$1
COMMAND=$2

case "$APP" in
    python|node|netcore|tomcat|drupal)
        case "$COMMAND" in
            start)
                start_app $APP
                ;;
            stop)
                stop_app $APP
                ;;
            restart)
                restart_app $APP
                ;;
            status)
                status_app $APP
                ;;
            logs)
                show_logs $APP
                ;;
            *)
                print_status $RED "❌ Unknown command: $COMMAND"
                show_usage
                exit 1
                ;;
        esac
        ;;
    all)
        case "$COMMAND" in
            start)
                start_all
                ;;
            stop)
                stop_all
                ;;
            restart)
                stop_all
                sleep 2
                start_all
                ;;
            status)
                status_all
                ;;
            logs)
                print_status $RED "❌ 'logs' command not available for 'all'. Use individual app names."
                exit 1
                ;;
            *)
                print_status $RED "❌ Unknown command: $COMMAND"
                show_usage
                exit 1
                ;;
        esac
        ;;
    *)
        print_status $RED "❌ Unknown application: $APP"
        show_usage
        exit 1
        ;;
esac

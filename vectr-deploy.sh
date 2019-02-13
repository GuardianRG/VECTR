#!/bin/bash
# -----------------------------------------------------------------------------------------
# PLEASE READ:
# * Please store this permanently in a safe place, this may create other files and logs
# * that should be kept for as long as you plan on using VECTR
#
# This installation file may create the following:
# 1. .env configuration file in the same directory as this file that MUST be kept
# 2. 'download_temp' folder for downloading VECTR release
# 3. Named folder for extracting the contents of downloaded VECTR release
# 4. Possible installation logs
# -----------------------------------------------------------------------------------------

if [ "$(id -u)" != "0" ]; then
	echo "Exiting... setup must be run as sudo/root.  Please run sudo ./$0."
    SCRIPTEXIT
	exit 1
fi

function showHelp ()
{
    echo "usage: $0 "
    echo "    -h | --help : Show Help"
    echo "    -e | --envfile <filepath> : Use existing ENV file "
    echo "    -r | --releasefile <filepath> : Use release file zip already on disk (EXPERIMENTAL, sets full offline mode)"
}

OFFLINE=false
ENV_FILE=""
RELEASE_FILE_SPECIFIED=""

# Get and parse CLI arguments
# https://stackoverflow.com/questions/14062895/bash-argument-case-for-args-in/14063511#14063511
while [[ $# -gt 0 ]] && ( [[ ."$1" = .--* ]] || [[ ."$1" = .-* ]] ) ;
do
    opt="$1";
    shift;
    case "$opt" in
        "--" ) break 2;;
        "--envfile" | "-e" )
            ENV_FILE="$1"; shift;;
        "--releasefile" | "-r" )
            RELEASE_FILE_SPECIFIED="$1"
            OFFLINE=true
            shift;;
        "--help" | "-h" )
            showHelp
            SCRIPTEXIT
            exit 0;;
        *)
            echo "Invalid option: $opt"
            SCRIPTEXIT
            exit 1;;
   esac
done

source "vectr-shared-methods.sh"
SCRIPTENTRY

RUNNING_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

ENV_FILE_NAME="$(getFileNameNoExt "$ENV_FILE")"

ENV_VECTR_DEPLOY_DIR=$(getEnvVar "VECTR_DEPLOY_DIR" "$ENV_FILE")

VECTR_APP_DIR="$ENV_VECTR_DEPLOY_DIR/app"

ENV_VECTR_DATA_DIR=$(getEnvVar "VECTR_DATA_DIR" "$ENV_FILE")
ENV_VECTR_OS_USER=$(getEnvVar "VECTR_OS_USER" "$ENV_FILE")

ENV_VECTR_RELEASE_URL=$(getEnvVar "VECTR_RELEASE_URL" "$ENV_FILE")
ENV_VECTR_DOWNLOAD_TEMP=$(getEnvVar "VECTR_DOWNLOAD_TEMP" "$ENV_FILE")
ENV_VECTR_INSTALLED_VERSION=$(getEnvVar "VECTR_INSTALLED_VERSION" "$ENV_FILE")

ENV_VECTR_CERT_COUNTRY=$(getEnvVar "VECTR_CERT_COUNTRY" "$ENV_FILE")
ENV_VECTR_CERT_STATE=$(getEnvVar "VECTR_CERT_STATE" "$ENV_FILE")
ENV_VECTR_CERT_LOCALITY=$(getEnvVar "VECTR_CERT_LOCALITY" "$ENV_FILE")
ENV_VECTR_CERT_ORG=$(getEnvVar "VECTR_CERT_ORG" "$ENV_FILE")

ENV_VECTR_HOSTNAME=$(getEnvVar "VECTR_HOSTNAME" "$ENV_FILE")
ENV_VECTR_PORT=$(getEnvVar "VECTR_PORT" "$ENV_FILE")
ENV_MONGO_PORT=$(getEnvVar "MONGO_PORT" "$ENV_FILE")

ENV_TAXII_CERT_DIR=$(getEnvVar "TAXII_CERT_DIR" "$ENV_FILE")
ENV_CAS_DIR=$(getEnvVar "CAS_DIR" "$ENV_FILE")

ENV_VECTR_NETWORK_SUBNET=$(getEnvVar "VECTR_NETWORK_SUBNET" "$ENV_FILE")
ENV_VECTR_NETWORK_NAME=$(getEnvVar "VECTR_NETWORK_NAME" "$ENV_FILE")

ENV_VECTR_TOMCAT_CONTAINER_NAME=$(getEnvVar "VECTR_TOMCAT_CONTAINER_NAME" "$ENV_FILE")
ENV_VECTR_MONGO_CONTAINER_NAME=$(getEnvVar "VECTR_MONGO_CONTAINER_NAME" "$ENV_FILE")

VECTR_SSL_CRT_ENV_KEYNAME="VECTR_SSL_CRT"
VECTR_SSL_KEY_ENV_KEYNAME="VECTR_SSL_KEY"
ENV_VECTR_SSL_CRT=$(getEnvVar "$VECTR_SSL_CRT_ENV_KEYNAME" "$ENV_FILE")
ENV_VECTR_SSL_KEY=$(getEnvVar "$VECTR_SSL_KEY_ENV_KEYNAME" "$ENV_FILE")

VECTR_ENV_INSTALLED_VER_KEYNAME="VECTR_INSTALLED_VERSION"


DEPLOY_DEFAULT_NETWORK_SUBNET="10.0.27.0/24"
DEPLOY_DEFAULT_NETWORK_NAME="vectr_bridge"
DEPLOY_DEFAULT_TOMCAT_CONTAINER_NAME="vectr_tomcat_sandbox1"
DEPLOY_DEFAULT_MONGO_CONTAINER_NAME="vectr_mongo_sandbox1"
DEPLOY_DEFAULT_DEPLOY_DIR="/opt/vectr"
DEPLOY_COMPOSE_YAML_FILE_PATH="docker-compose.yml"
DEPLOY_SECONDARY_YAML_FILE_PATH="devSsl.yml"
DEPLOY_DEFAULT_DATA_DIR="/var/data/sandbox1"
DEPLOY_DEFAULT_PORTS="\"8081:8443\""
DEPLOY_DEFAULT_MONGO_PORTS="\"27018:27017\""
DEPLOY_DEFAULT_TAXII_CERT_DIR="/opt/taxii/certs/"
DEPLOY_DEFAULT_CAS_DIR="/opt/cas/"

function checkContinueDeployment () 
{
    if [ "$1" -ne 1 ]; then
        # stop deployment, throw error
        echo " ERROR: VECTR Deployment can not continue. Please correct any issues marked above or check installation logs."
        SCRIPTEXIT
        exit 1
    fi
}

function deployVectr ()
{ 
    #local JAVA_OK=$(javaOk)
    #printStatusMark "$JAVA_OK" 
    #printf " Java version 1.8 or greater\n"

    # -------------------------------------------------------------------------------------------
    # Step 1: Check the docker version to make sure it supports our compose features 
    # -------------------------------------------------------------------------------------------
    local DOCKER_OK=$(dockerVersionOk)
    printStatusMark "$DOCKER_OK" 
    printf " Docker ce version 17.03 or Docker engine 1.10 or greater\n"
    checkContinueDeployment "$DOCKER_OK"

    # -------------------------------------------------------------------------------------------
    # Step 2: Make sure curl is installed (really, ubuntu?) 
    # -------------------------------------------------------------------------------------------
    if [ "$OFFLINE" != true ]; then
        local CURL_OK=$(curlInstalled)
        printStatusMark "$CURL_OK" 
        printf " Curl is installed\n"
        checkContinueDeployment "$CURL_OK"
    fi

    # -------------------------------------------------------------------------------------------
    # Step 3: Make sure the VECTR user specified actually exists on the operating system
    # -------------------------------------------------------------------------------------------
    local USER_EXISTS=$(userExists "$ENV_VECTR_OS_USER")
    printStatusMark "$USER_EXISTS" 
    printf " VECTR OS user exists\n"

    checkContinueDeployment "$USER_EXISTS"

    # -------------------------------------------------------------------------------------------
    # Step 4: Verify that VECTR deployment directory exists and if not, make a new directory
    # -------------------------------------------------------------------------------------------
    local VECTR_DEPLOY_DIR_EXISTS=$(dirExists "$ENV_VECTR_DEPLOY_DIR")
    if [ "$VECTR_DEPLOY_DIR_EXISTS" -ne 1 ]
    then
        local VECTR_MAKE_DEPLOY_DIR=$(makeDir "$ENV_VECTR_DEPLOY_DIR")
        printStatusMark "$VECTR_MAKE_DEPLOY_DIR"
        printf " Made VECTR deploy directory\n"

        local VECTR_DEPLOY_DIR_EXISTS=$(dirExists "$ENV_VECTR_DEPLOY_DIR")
        printStatusMark "$VECTR_DEPLOY_DIR_EXISTS" 
        printf " VECTR deploy directory exists\n"
    else
        printStatusMark "$VECTR_DEPLOY_DIR_EXISTS" 
        printf " VECTR deploy directory exists\n"
    fi
    checkContinueDeployment "$VECTR_DEPLOY_DIR_EXISTS"



    # -------------------------------------------------------------------------------------------
    # Step 6: Check VECTR download temp directory exists and create if not
    # -------------------------------------------------------------------------------------------
    local VECTR_DOWNLOAD_TEMP_EXISTS=$(dirExists "$ENV_VECTR_DOWNLOAD_TEMP")
    if [ "$VECTR_DOWNLOAD_TEMP_EXISTS" -ne 1 ]
    then
        local VECTR_MAKE_DOWNLOAD_TEMP_DIR=$(makeDir "$ENV_VECTR_DOWNLOAD_TEMP")
        printStatusMark "$VECTR_MAKE_DOWNLOAD_TEMP_DIR"
        printf " Made VECTR download temp dir\n"

        local VECTR_DOWNLOAD_TEMP_EXISTS=$(dirExists "$ENV_VECTR_DOWNLOAD_TEMP")
        printStatusMark "$VECTR_DOWNLOAD_TEMP_EXISTS" 
        printf " VECTR download temp directory exists\n"
    else
        printStatusMark "$VECTR_DOWNLOAD_TEMP_EXISTS" 
        printf " VECTR download temp directory exists\n"
    fi
    checkContinueDeployment "$VECTR_DEPLOY_DIR_EXISTS"

    # -------------------------------------------------------------------------------------------
    # Step 7: Check VECTR download temp directory permissions for VECTR user account and if they're bad attempt to fix and recheck
    # -------------------------------------------------------------------------------------------
    local VECTR_DOWNLOAD_TEMP_DIR_PERMS_CHECK=$(dirPermsCheck "$ENV_VECTR_OS_USER" "$ENV_VECTR_DOWNLOAD_TEMP")
    if [ "$VECTR_DOWNLOAD_TEMP_DIR_PERMS_CHECK" -ne 1 ]
    then
        local VECTR_FIX_DOWNLOAD_TEMP_DIR_PERMS=$(fixDirPerms "$ENV_VECTR_OS_USER" "$ENV_VECTR_DOWNLOAD_TEMP")
        printStatusMark 1
        printf " Fix VECTR download temp directory permissions\n"

        local VECTR_DOWNLOAD_TEMP_DIR_PERMS_CHECK=$(dirPermsCheck "$ENV_VECTR_OS_USER" "$ENV_VECTR_DOWNLOAD_TEMP")
        printStatusMark "$VECTR_DOWNLOAD_TEMP_DIR_PERMS_CHECK" 
        printf " VECTR download temp directory permissions are OK\n"
    else
        printStatusMark "$VECTR_DOWNLOAD_TEMP_DIR_PERMS_CHECK" 
        printf " VECTR download temp permissions are OK\n"
    fi
    checkContinueDeployment "$VECTR_DOWNLOAD_TEMP_DIR_PERMS_CHECK"
    
    # -------------------------------------------------------------------------------------------
    # Step 8: Get VECTR Release URL for pulling down latest VECTR Release Download
    # -------------------------------------------------------------------------------------------
    if [ "$OFFLINE" != true ]; then
        local VECTR_RELEASE_FILE_URL=$(getLatestVectrReleaseFileUrl "$ENV_VECTR_RELEASE_URL")
        if [ -z "$VECTR_RELEASE_FILE_URL" ]; then
            local VECTR_RELEASE_FILE_URL_PARSE_SUCCESS=0
        else
            local VECTR_RELEASE_FILE_URL_PARSE_SUCCESS=1
        fi
        printStatusMark "$VECTR_RELEASE_FILE_URL_PARSE_SUCCESS"
        printf " VECTR release file URL parsed for download\n"
    else
        local VECTR_RELEASE_FILE_URL="$RELEASE_FILE_SPECIFIED"
    fi

    # -------------------------------------------------------------------------------------------
    # Step 9: Get VECTR Release Zip file name for comparison and storing in ENV file if successfully deployed
    # -------------------------------------------------------------------------------------------
    
    local VECTR_RELEASE_ZIP_NAME=$(getLatestVectrReleaseZipFile $VECTR_RELEASE_FILE_URL)
    if [ -z "$VECTR_RELEASE_ZIP_NAME" ]; then
        local VECTR_RELEASE_ZIP_NAME_PARSE_SUCCESS=0
    else
        local VECTR_RELEASE_ZIP_NAME_PARSE_SUCCESS=1
    fi
    printStatusMark "$VECTR_RELEASE_ZIP_NAME_PARSE_SUCCESS"
    printf " VECTR release zip name found for comparison\n"
    
    # -------------------------------------------------------------------------------------------
    # Step 10: Check to see if a VECTR vesion was previously installed or downloaded, download if doesn't exist or not up to date
    # -------------------------------------------------------------------------------------------
    # @TODO - This logic can be simplified at a later date

    
    local VECTR_DOWNLOADED_VER_OK=0
    local VECTR_DOWNLOADED_NEW=0
    
    if [ "$OFFLINE" != true ]; then    
        if [ ! -z "$ENV_VECTR_INSTALLED_VERSION" ]; then
            if [ $VECTR_RELEASE_ZIP_NAME != "$ENV_VECTR_INSTALLED_VERSION" ]; then
                # This is the upgrade code path
                downloadLatestVectrRelease $ENV_VECTR_OS_USER $VECTR_RELEASE_FILE_URL $ENV_VECTR_DOWNLOAD_TEMP $RUNNING_DIR
                
                local VECTR_RELEASE_FILE_DOWNLOADED=$(fileExists "$ENV_VECTR_DOWNLOAD_TEMP/$VECTR_RELEASE_ZIP_NAME" )
                printStatusMark "$VECTR_RELEASE_FILE_DOWNLOADED"
                printf " VECTR release zip downloaded to temporary download dir for upgrade\n"
                local VECTR_DOWNLOADED_VER_OK="$VECTR_RELEASE_FILE_DOWNLOADED"
                local VECTR_DOWNLOADED_NEW="$VECTR_RELEASE_FILE_DOWNLOADED"

            else
                # current version of zip exists, continue
                printStatusMark 1
                printf " VECTR release in temporary download dir is current\n"
                local VECTR_DOWNLOADED_VER_OK=1
            fi
        else
            # new installation code path

            local VECTR_RELEASE_FILE_EXISTS=$(fileExists "$ENV_VECTR_DOWNLOAD_TEMP/$VECTR_RELEASE_ZIP_NAME")
            if [ "$VECTR_RELEASE_FILE_EXISTS" -ne 1 ]
            then
                downloadLatestVectrRelease $ENV_VECTR_OS_USER $VECTR_RELEASE_FILE_URL $ENV_VECTR_DOWNLOAD_TEMP $RUNNING_DIR

                local VECTR_RELEASE_FILE_DOWNLOADED=$(fileExists "$ENV_VECTR_DOWNLOAD_TEMP/$VECTR_RELEASE_ZIP_NAME")
                printStatusMark "$VECTR_RELEASE_FILE_DOWNLOADED"
                printf " VECTR release zip downloaded to temporary download dir for new installation\n"
                local VECTR_DOWNLOADED_VER_OK="$VECTR_RELEASE_FILE_DOWNLOADED"
                local VECTR_DOWNLOADED_NEW="$VECTR_RELEASE_FILE_DOWNLOADED"
            else
                printStatusMark 1
                printf " VECTR release zip already exists in temp download dir despite not being installed\n"
                local VECTR_DOWNLOADED_VER_OK=1
            fi
        fi
        checkContinueDeployment "$VECTR_DOWNLOADED_VER_OK"
    else
        # release file is specified
        if [ ! -z "$ENV_VECTR_INSTALLED_VERSION" ]; then
            if [ $VECTR_RELEASE_ZIP_NAME != "$ENV_VECTR_INSTALLED_VERSION" ]; then
                local VECTR_RELEASE_FILE_DOWNLOADED=$(fileExists "$VECTR_RELEASE_FILE_URL" )
                printStatusMark "$VECTR_RELEASE_FILE_DOWNLOADED"
                printf " VECTR release zip exists at install location\n"
                local VECTR_DOWNLOADED_VER_OK="$VECTR_RELEASE_FILE_DOWNLOADED"
                local VECTR_DOWNLOADED_NEW="$VECTR_RELEASE_FILE_DOWNLOADED"

            else
                # current version of zip exists, continue
                printStatusMark 1
                printf " VECTR release in specified dir is current\n"
                local VECTR_DOWNLOADED_VER_OK=1
            fi
        fi
    fi

    # -------------------------------------------------------------------------------------------
    # Step 11: Extract VECTR zip file if extracted folder doesn't exist
    # -------------------------------------------------------------------------------------------   
    local VECTR_RELEASE_FOLDER_NAME=${VECTR_RELEASE_ZIP_NAME%.*}

    local VECTR_EXTRACT_DIR_EXISTS=$(dirExists "$ENV_VECTR_DOWNLOAD_TEMP/$VECTR_RELEASE_FOLDER_NAME")
    if [ "$VECTR_EXTRACT_DIR_EXISTS" -ne 1 ]
    then
        local EXTRACT_FROM_LOCATION
        if [ "$OFFLINE" != true ]; then  
            EXTRACT_FROM_LOCATION="$ENV_VECTR_DOWNLOAD_TEMP/$VECTR_RELEASE_ZIP_NAME"
        else
            EXTRACT_FROM_LOCATION="$VECTR_RELEASE_FILE_URL"
        fi
        local VECTR_RELEASE_EXTRACT=$(extractVectrRelease "$ENV_VECTR_OS_USER" "$EXTRACT_FROM_LOCATION" "$ENV_VECTR_DOWNLOAD_TEMP/$VECTR_RELEASE_FOLDER_NAME")

        local VECTR_EXTRACT_DIR_EXISTS=$(dirExists "$ENV_VECTR_DOWNLOAD_TEMP/$VECTR_RELEASE_FOLDER_NAME")
        printStatusMark "$VECTR_EXTRACT_DIR_EXISTS" 
        printf " Extracted VECTR downloaded release to $ENV_VECTR_DOWNLOAD_TEMP/$VECTR_RELEASE_FOLDER_NAME\n"
        
    else
        printStatusMark "$VECTR_EXTRACT_DIR_EXISTS" 
        printf " VECTR extracted release folder exists\n"
    fi
    checkContinueDeployment "$VECTR_EXTRACT_DIR_EXISTS"

    
    
    # -------------------------------------------------------------------------------------------
    # Step 12: Verify extracted VECTR release files
    # -------------------------------------------------------------------------------------------   
    local VECTR_VERIFY_RELEASE=$(verifyVectrReleaseHelper "$ENV_VECTR_DOWNLOAD_TEMP/$VECTR_RELEASE_FOLDER_NAME")
    printStatusMark "$VECTR_VERIFY_RELEASE" 
    printf " Verify extracted VECTR release\n"

    checkContinueDeployment "$VECTR_VERIFY_RELEASE"

    # -------------------------------------------------------------------------------------------
    # Step 13: Copy extracted VECTR release files to VECTR deploy directory if it's newly downloaded or nothing exists in there
    # -------------------------------------------------------------------------------------------   
    local VECTR_VERIFY_DEPLOY=$(verifyVectrReleaseHelper "$VECTR_APP_DIR")

    if [ "$VECTR_DOWNLOADED_NEW" -eq 1 ] || [ "$VECTR_VERIFY_DEPLOY" -ne 1 ]; then 
        # if at least config folder exists let's backup
        VECTR_RELEASE_EXISTS=$(dirExists "$VECTR_APP_DIR/config")
        if [ $VECTR_RELEASE_EXISTS -eq 1 ]; then
            local ZIP_BACKUP_RES=$(backupConfigFiles "$VECTR_APP_DIR")
        fi

        local COPIED_RELEASE_FILES=$(copyFilesToFolder "$ENV_VECTR_DOWNLOAD_TEMP/$VECTR_RELEASE_FOLDER_NAME" "$VECTR_APP_DIR")
        local VECTR_FIX_COPIED_RELEASE_PERMS=$(fixDirPerms "$ENV_VECTR_OS_USER" "$VECTR_APP_DIR")

        local VECTR_DEPLOY_DIR_POST_PERMS_CHECK=$(dirPermsCheck "$ENV_VECTR_OS_USER" "$VECTR_APP_DIR")
        printStatusMark "$VECTR_DEPLOY_DIR_POST_PERMS_CHECK" 
        printf " VECTR deployed and check directory permissions are OK after deployment\n"

        local VECTR_VERIFY_DEPLOY=$(verifyVectrReleaseHelper "$VECTR_APP_DIR")
    fi

    
    printStatusMark "$VECTR_VERIFY_DEPLOY" 
    printf " Verify VECTR deployed to VECTR deploy folder\n"

    checkContinueDeployment "$VECTR_VERIFY_DEPLOY"

    # -------------------------------------------------------------------------------------------
    # Step 14: Generate certs if needed or copy certs to correct config dir
    # -------------------------------------------------------------------------------------------

    local CRT_FILENAME
    local KEY_FILENAME
    # VECTR app expects ssl.crt and ssl.key so this has to be renamed like the self signed cert
    local SELF_SIGNED_CERT_NAME="ssl"
    CRT_FILENAME="$SELF_SIGNED_CERT_NAME.crt"
    KEY_FILENAME="$SELF_SIGNED_CERT_NAME.key"
    if [ -z "$ENV_VECTR_SSL_CRT" ] || [ -z "$ENV_VECTR_SSL_KEY" ] || [ ! -f "$ENV_VECTR_SSL_CRT" ] || [ ! -f "$ENV_VECTR_SSL_KEY" ]; then
        local SELF_SIGNED_CERT_CLI_OUTPUT
        SELF_SIGNED_CERT_CLI_OUTPUT=$(generateSelfSignedCert "$ENV_VECTR_CERT_COUNTRY" "$ENV_VECTR_CERT_STATE" "$ENV_VECTR_CERT_LOCALITY" "$ENV_VECTR_CERT_ORG" "$ENV_VECTR_HOSTNAME" "$VECTR_APP_DIR" "$SELF_SIGNED_CERT_NAME")
        
        local CERTS_GENERATED_OK
        CERTS_GENERATED_OK=1
        # @TODO - build this function
        #CERTS_GENERATED_OK=$(checkGeneratedCertOutput "$SELF_SIGNED_CERT_CLI_OUTPUT")

        printStatusMark "$CERTS_GENERATED_OK" 
        printf " Generated self-signed SSL certs\n"
    else
        if [ ! -f "$VECTR_APP_DIR/config/$CRT_FILENAME" ] || [ ! -f "$VECTR_APP_DIR/config/$KEY_FILENAME" ]; then
            cp "$ENV_VECTR_SSL_CRT" "$VECTR_APP_DIR/config/$CRT_FILENAME" 
            chown "${ENV_VECTR_OS_USER}" "$VECTR_APP_DIR/config/$CRT_FILENAME"

            cp "$ENV_VECTR_SSL_KEY" "$VECTR_APP_DIR/config/$KEY_FILENAME" 
            chown "${ENV_VECTR_OS_USER}" "$VECTR_APP_DIR/config/$KEY_FILENAME"

            printStatusMark 1 
            printf " Attempting to use existing SSL certs specified, moving to VECTR config dir and renaming\n"
        else 
            printStatusMark 1 
            printf " Attempting to use existing SSL certs in VECTR config folder\n"
        fi
    fi

    # make ssl.key file readable by all (not ideal, but Ubuntu's docker perms are a pain)
    # @TODO - get rid of this if we're not supporting snap installs?
    chmod a+r "$VECTR_APP_DIR/config/$KEY_FILENAME"

    # -------------------------------------------------------------------------------------------
    # Step 15: Verify SSL certs
    # ------------------------------------------------------------------------------------------- 
    local VECTR_VERIFY_CERTS
    VECTR_VERIFY_CERTS=$(verifySSLCert "$VECTR_APP_DIR/config/$KEY_FILENAME" "$VECTR_APP_DIR/config/$CRT_FILENAME")
    
    printStatusMark "$VECTR_VERIFY_CERTS" 
    printf " Verify VECTR SSL certs in config folder\n"

    checkContinueDeployment "$VECTR_VERIFY_CERTS"

    # -------------------------------------------------------------------------------------------
    # Step 16: Write SSL cert location to ENV file
    # ------------------------------------------------------------------------------------------- 

    local VECTR_FINAL_SSL_KEY_FILE
    VECTR_FINAL_SSL_KEY_FILE="$VECTR_APP_DIR/config/$KEY_FILENAME"
    local VECTR_FINAL_SSL_CRT_FILE
    VECTR_FINAL_SSL_CRT_FILE="$VECTR_APP_DIR/config/$CRT_FILENAME"

    local VECTR_WRITE_SSL_KEY_CONF=$(writeKeyValueToEnvFile "$ENV_FILE" "$VECTR_SSL_KEY_ENV_KEYNAME" "$VECTR_FINAL_SSL_KEY_FILE")
    local VECTR_WRITE_SSL_CRT_CONF=$(writeKeyValueToEnvFile "$ENV_FILE" "$VECTR_SSL_CRT_ENV_KEYNAME" "$VECTR_FINAL_SSL_CRT_FILE")

    # -------------------------------------------------------------------------------------------
    # Step 17: Verify ENV file SSL contents 
    # ------------------------------------------------------------------------------------------- 

    local SSL_KEY_FILE_CHECK
    SSL_KEY_FILE_CHECK="$(envFileKeyEqualsValue "$ENV_FILE" "$VECTR_SSL_KEY_ENV_KEYNAME" "$VECTR_FINAL_SSL_KEY_FILE")"
    local SSL_CRT_FILE_CHECK
    SSL_CRT_FILE_CHECK="$(envFileKeyEqualsValue "$ENV_FILE" "$VECTR_SSL_CRT_ENV_KEYNAME" "$VECTR_FINAL_SSL_CRT_FILE")"

    local ENV_FILE_SSL_FILES_CHECK
    if [ $SSL_KEY_FILE_CHECK -eq 1 ] && [ $SSL_CRT_FILE_CHECK -eq 1 ]; then
        ENV_FILE_SSL_FILES_CHECK=1
    else
        ENV_FILE_SSL_FILES_CHECK=0
    fi

    printStatusMark "$ENV_FILE_SSL_FILES_CHECK" 
    printf " Verify VECTR SSL certs set in ENV file\n"

    checkContinueDeployment "$ENV_FILE_SSL_FILES_CHECK"

    # -------------------------------------------------------------------------------------------
    # Step 18: Modify VECTR deploy directory configuration files to match supplied env settings IF NOT SET
    # ------------------------------------------------------------------------------------------- 

    local DOCKER_COMPOSE_YAML_DEPLOY_DIR_EXISTS
    DOCKER_COMPOSE_YAML_DEPLOY_DIR_EXISTS="$(yamlConfigItemExists "$VECTR_APP_DIR/$DEPLOY_COMPOSE_YAML_FILE_PATH" "$VECTR_APP_DIR/wars")"
    if [ "$DOCKER_COMPOSE_YAML_DEPLOY_DIR_EXISTS" -ne 1 ]; then
        local EDIT_DOCKER_COMPOSE_YAML_DEPLOY_DIR
        EDIT_DOCKER_COMPOSE_YAML_DEPLOY_DIR="$(editYamlConfigItem "$VECTR_APP_DIR/$DEPLOY_COMPOSE_YAML_FILE_PATH" "$DEPLOY_DEFAULT_DEPLOY_DIR" "$VECTR_APP_DIR")"
    fi

    local SECONDARY_YAML_DEPLOY_DIR_EXISTS
    SECONDARY_YAML_DEPLOY_DIR_EXISTS="$(yamlConfigItemExists "$VECTR_APP_DIR/$DEPLOY_SECONDARY_YAML_FILE_PATH" "$VECTR_APP_DIR/config/server.xml")"
    if [ "$SECONDARY_YAML_DEPLOY_DIR_EXISTS" -ne 1 ]; then
        local EDIT_SECONDARY_YAML_DEPLOY_DIR
        EDIT_SECONDARY_YAML_DEPLOY_DIR="$(editYamlConfigItem "$VECTR_APP_DIR/$DEPLOY_SECONDARY_YAML_FILE_PATH" "$DEPLOY_DEFAULT_DEPLOY_DIR" "$VECTR_APP_DIR")"
    fi

    local SECONDARY_YAML_DATA_DIR_EXISTS
    SECONDARY_YAML_DATA_DIR_EXISTS="$(yamlConfigItemExists "$VECTR_APP_DIR/$DEPLOY_SECONDARY_YAML_FILE_PATH" "$ENV_VECTR_DATA_DIR")"
    if [ "$SECONDARY_YAML_DATA_DIR_EXISTS" -ne 1 ]; then
        local EDIT_SECONDARY_YAML_DATA_DIR
        EDIT_SECONDARY_YAML_DATA_DIR="$(editYamlConfigItem "$VECTR_APP_DIR/$DEPLOY_SECONDARY_YAML_FILE_PATH" "$DEPLOY_DEFAULT_DATA_DIR" "$ENV_VECTR_DATA_DIR")"
    fi

    local SECONDARY_YAML_SSL_PORT_MAP_EXISTS
    SECONDARY_YAML_SSL_PORT_MAP_EXISTS="$(yamlConfigItemExists "$VECTR_APP_DIR/$DEPLOY_SECONDARY_YAML_FILE_PATH" "\"$ENV_VECTR_PORT")"
    if [ "$SECONDARY_YAML_SSL_PORT_MAP_EXISTS" -ne 1 ]; then
        local EDIT_SECONDARY_YAML_SSL_PORT
        EDIT_SECONDARY_YAML_SSL_PORT="$(editYamlConfigItem "$VECTR_APP_DIR/$DEPLOY_SECONDARY_YAML_FILE_PATH" "$DEPLOY_DEFAULT_PORTS" "\"$ENV_VECTR_PORT:8443\"")"
    fi

    local SECONDARY_YAML_MONGO_PORT_MAP_EXISTS
    SECONDARY_YAML_MONGO_PORT_MAP_EXISTS="$(yamlConfigItemExists "$VECTR_APP_DIR/$DEPLOY_SECONDARY_YAML_FILE_PATH" "\"$ENV_MONGO_PORT")"
    if [ "$SECONDARY_YAML_MONGO_PORT_MAP_EXISTS" -ne 1 ]; then
        local EDIT_SECONDARY_YAML_MONGO_PORT
        EDIT_SECONDARY_YAML_MONGO_PORT="$(editYamlConfigItem "$VECTR_APP_DIR/$DEPLOY_SECONDARY_YAML_FILE_PATH" "$DEPLOY_DEFAULT_MONGO_PORTS" "\"$ENV_MONGO_PORT:27017\"")"
    fi

    # DEPLOY_DEFAULT_TOMCAT_CONTAINER_NAME="vectr_tomcat_sandbox1"
    # DEPLOY_DEFAULT_MONGO_CONTAINER_NAME="vectr_mongo_sandbox1"
    # Network config items
    # - subnet: 10.0.27.0/24
    local DOCKER_COMPOSE_YAML_NETWORK_SUBNET_EXISTS
    DOCKER_COMPOSE_YAML_NETWORK_SUBNET_EXISTS="$(yamlConfigItemExists "$VECTR_APP_DIR/$DEPLOY_COMPOSE_YAML_FILE_PATH" "$ENV_VECTR_NETWORK_SUBNET")"
    if [ "$DOCKER_COMPOSE_YAML_NETWORK_SUBNET_EXISTS" -ne 1 ]; then
        local EDIT_DOCKER_COMPOSE_YAML_NETWORK_SUBNET
        EDIT_DOCKER_COMPOSE_YAML_NETWORK_SUBNET="$(replaceValueInFile "$VECTR_APP_DIR/$DEPLOY_COMPOSE_YAML_FILE_PATH" "$DEPLOY_DEFAULT_NETWORK_SUBNET" "$ENV_VECTR_NETWORK_SUBNET")"
    fi

    # vectr_bridge
    local DOCKER_COMPOSE_YAML_NETWORK_NAME_EXISTS
    DOCKER_COMPOSE_YAML_NETWORK_NAME_EXISTS="$(yamlConfigItemExists "$VECTR_APP_DIR/$DEPLOY_COMPOSE_YAML_FILE_PATH" "$ENV_VECTR_NETWORK_NAME")"
    if [ "$DOCKER_COMPOSE_YAML_NETWORK_NAME_EXISTS" -ne 1 ]; then
        local EDIT_DOCKER_COMPOSE_YAML_NETWORK_NAME
        EDIT_DOCKER_COMPOSE_YAML_NETWORK_NAME="$(replaceValueInFile "$VECTR_APP_DIR/$DEPLOY_COMPOSE_YAML_FILE_PATH" "$DEPLOY_DEFAULT_NETWORK_NAME" "$ENV_VECTR_NETWORK_NAME")"
    fi

    # secondary yaml
    # vectr_tomcat_sandbox1
    local SECONDARY_YAML_TOMCAT_CONTAINER_NAME_EXISTS
    SECONDARY_YAML_TOMCAT_CONTAINER_NAME_EXISTS="$(yamlConfigItemExists "$VECTR_APP_DIR/$DEPLOY_SECONDARY_YAML_FILE_PATH" "$ENV_VECTR_TOMCAT_CONTAINER_NAME")"
    if [ "$SECONDARY_YAML_TOMCAT_CONTAINER_NAME_EXISTS" -ne 1 ]; then
        local EDIT_SECONDARY_YAML_TOMCAT_CONTAINER_NAME
        EDIT_SECONDARY_YAML_TOMCAT_CONTAINER_NAME="$(replaceValueInFile "$VECTR_APP_DIR/$DEPLOY_SECONDARY_YAML_FILE_PATH" "$DEPLOY_DEFAULT_TOMCAT_CONTAINER_NAME" "$ENV_VECTR_TOMCAT_CONTAINER_NAME")"
    fi

    # vectr_mongo_sandbox1
    local SECONDARY_YAML_MONGO_CONTAINER_NAME_EXISTS
    SECONDARY_YAML_MONGO_CONTAINER_NAME_EXISTS="$(yamlConfigItemExists "$VECTR_APP_DIR/$DEPLOY_SECONDARY_YAML_FILE_PATH" "$ENV_VECTR_MONGO_CONTAINER_NAME")"
    if [ "$SECONDARY_YAML_MONGO_CONTAINER_NAME_EXISTS" -ne 1 ]; then
        local EDIT_SECONDARY_YAML_MONGO_CONTAINER_NAME
        EDIT_SECONDARY_YAML_MONGO_CONTAINER_NAME="$(replaceValueInFile "$VECTR_APP_DIR/$DEPLOY_SECONDARY_YAML_FILE_PATH" "$DEPLOY_DEFAULT_MONGO_CONTAINER_NAME" "$ENV_VECTR_MONGO_CONTAINER_NAME")"
    fi

    # Wrap in conditionals to detect if they're actually there?

    # NOTE!!! These are followed by a trailing /, this might cause issues... probably need to build in some leniency in the yamlConfigItemExists function
    local DOCKER_COMPOSE_TAXII_CERT_DIR_EXISTS
    DOCKER_COMPOSE_TAXII_CERT_DIR_EXISTS="$(yamlConfigItemExists "$VECTR_APP_DIR/$DEPLOY_COMPOSE_YAML_FILE_PATH" "$ENV_TAXII_CERT_DIR/")"
    if [ "$DOCKER_COMPOSE_TAXII_CERT_DIR_EXISTS" -ne 1 ]; then
        local EDIT_DOCKER_COMPOSE_YAML_TAXII_CERT_DIR
        EDIT_DOCKER_COMPOSE_YAML_TAXII_CERT_DIR="$(editYamlConfigItem "$VECTR_APP_DIR/$DEPLOY_COMPOSE_YAML_FILE_PATH" "$DEPLOY_DEFAULT_TAXII_CERT_DIR" "$ENV_TAXII_CERT_DIR/")"
    fi

    local DOCKER_COMPOSE_CAS_DIR_EXISTS
    DOCKER_COMPOSE_CAS_DIR_EXISTS="$(yamlConfigItemExists "$VECTR_APP_DIR/$DEPLOY_COMPOSE_YAML_FILE_PATH" "$ENV_CAS_DIR/")"
    if [ "$DOCKER_COMPOSE_CAS_DIR_EXISTS" -ne 1 ]; then
        local EDIT_DOCKER_COMPOSE_YAML_CAS_DIR
        EDIT_DOCKER_COMPOSE_YAML_CAS_DIR="$(editYamlConfigItem "$VECTR_APP_DIR/$DEPLOY_COMPOSE_YAML_FILE_PATH" "$DEPLOY_DEFAULT_CAS_DIR" "$ENV_CAS_DIR/")"
    fi

    # -------------------------------------------------------------------------------------------
    # Step 19: Verify YAML configuration changes made by installer
    # ------------------------------------------------------------------------------------------- 

    local COMPOSE_DEPLOY_DIRS_ARR=("wars" "config" "backup" "migrationlogs" "migrationbackups")

    local COMPOSE_CONFIG_ITEM_EXISTS_RES
    local COMPOSE_CONFIG_ITEMS_EXIST=1
    for COMPOSE_DEPLOY_DIR in "${COMPOSE_DEPLOY_DIRS_ARR[@]}"; do
        COMPOSE_CONFIG_ITEM_EXISTS_RES="$(yamlConfigItemExists "$VECTR_APP_DIR/$DEPLOY_COMPOSE_YAML_FILE_PATH" "$VECTR_APP_DIR/$COMPOSE_DEPLOY_DIR")"

        if [ "$COMPOSE_CONFIG_ITEM_EXISTS_RES" -eq 0 ]; then
            COMPOSE_CONFIG_ITEMS_EXIST=0
        fi
    done

    # TAXII/CAS future items
    # DEV NOTE - This seems to cause the mose issues with older versions, not sure it's necessary yet
    #local COMPOSE_TAXII_CERT_EXISTS_RES="$(yamlConfigItemExists "$VECTR_APP_DIR/$DEPLOY_COMPOSE_YAML_FILE_PATH" "$ENV_TAXII_CERT_DIR/")"
    #local COMPOSE_CAS_DIR_EXISTS="$(yamlConfigItemExists "$VECTR_APP_DIR/$DEPLOY_COMPOSE_YAML_FILE_PATH" "$ENV_CAS_DIR/")"

    #if [ "$COMPOSE_CONFIG_ITEMS_EXIST" -eq 1 ] && ( [ "$COMPOSE_TAXII_CERT_EXISTS_RES" -eq 0 ] || [ "$COMPOSE_CAS_DIR_EXISTS" -eq 0 ] ); then
    #    COMPOSE_CONFIG_ITEMS_EXIST=0
    #fi

    printStatusMark "$COMPOSE_CONFIG_ITEMS_EXIST"
    printf " VECTR docker-compose file checks out\n"

    checkContinueDeployment "$COMPOSE_CONFIG_ITEMS_EXIST"

    # Check secondary docker configuration file

    local SECONDARY_CONFIG_ITEMS_ARR=("$VECTR_APP_DIR/config/server.xml" "$VECTR_APP_DIR/config/$CRT_FILENAME" "$VECTR_APP_DIR/config/$KEY_FILENAME" "$ENV_VECTR_DATA_DIR" "\"$ENV_VECTR_PORT")

    local SECONDARY_CONFIG_ITEM_EXISTS_RES
    local SECONDARY_CONFIG_ITEMS_EXIST=1
    for SECONDARY_CONFIG_ITEM in "${SECONDARY_CONFIG_ITEMS_ARR[@]}"; do
        SECONDARY_CONFIG_ITEM_EXISTS_RES="$(yamlConfigItemExists "$VECTR_APP_DIR/$DEPLOY_SECONDARY_YAML_FILE_PATH" "$SECONDARY_CONFIG_ITEM")"

        if [ "$SECONDARY_CONFIG_ITEM_EXISTS_RES" -eq 0 ]; then
            echo "checking $SECONDARY_CONFIG_ITEM  failed"
            SECONDARY_CONFIG_ITEMS_EXIST=0
        fi
    done

    printStatusMark "$SECONDARY_CONFIG_ITEMS_EXIST"
    printf " VECTR secondary docker config file checks out\n"

    checkContinueDeployment "$SECONDARY_CONFIG_ITEMS_EXIST"

    # -------------------------------------------------------------------------------------------
    # Step 20: Check VECTR deployment directory permissions for VECTR user account and if they're bad attempt to fix and recheck
    # -------------------------------------------------------------------------------------------
    local VECTR_DEPLOY_DIR_PERMS_CHECK=$(dirPermsCheck "$ENV_VECTR_OS_USER" "$ENV_VECTR_DEPLOY_DIR")
    if [ "$VECTR_DEPLOY_DIR_PERMS_CHECK" -ne 1 ]
    then
        local VECTR_FIX_DEPLOY_DIR_PERMS=$(fixDirPerms "$ENV_VECTR_OS_USER" "$ENV_VECTR_DEPLOY_DIR")
        printStatusMark 1
        printf " Fix VECTR deploy directory permissions\n"

        local VECTR_DEPLOY_DIR_PERMS_CHECK=$(dirPermsCheck "$ENV_VECTR_OS_USER" "$ENV_VECTR_DEPLOY_DIR")
        printStatusMark "$VECTR_DEPLOY_DIR_PERMS_CHECK" 
        printf " VECTR deploy directory permissions are OK\n"
    else
        printStatusMark "$VECTR_DEPLOY_DIR_PERMS_CHECK" 
        printf " VECTR deploy directory permissions are OK\n"
    fi
    checkContinueDeployment "$VECTR_DEPLOY_DIR_PERMS_CHECK"


    # -------------------------------------------------------------------------------------------
    # Step 21: Edit /etc/hosts to add hostname and 127.0.0.1 if doesn't exist
    # ------------------------------------------------------------------------------------------- 

    local HOSTS_VECTR_HOSTNAME_EXISTS

    HOSTS_VECTR_HOSTNAME_EXISTS="$(checkHostExists "$ENV_VECTR_HOSTNAME")"
    if [ "$HOSTS_VECTR_HOSTNAME_EXISTS" -ne 1 ]; then
        local HOSTS_ADD_VECTR_HOSTNAME
        HOSTS_ADD_VECTR_HOSTNAME="$(addHost "127.0.0.1" "$ENV_VECTR_HOSTNAME")"

        printStatusMark 1
        printf " VECTR local /etc/hosts hostname created\n"

        HOSTS_VECTR_HOSTNAME_EXISTS="$(checkHostExists "$ENV_VECTR_HOSTNAME")"
    fi

    printStatusMark "$SECONDARY_CONFIG_ITEMS_EXIST"
    printf " VECTR local /etc/hosts hostname exists\n"

    # -------------------------------------------------------------------------------------------
    # Step 22: Mark VECTR_INSTALLED_VERSION in env file supplied
    # ------------------------------------------------------------------------------------------- 

    local VECTR_WRITE_INSTALLED_VER=$(writeKeyValueToEnvFile "$ENV_FILE" "$VECTR_ENV_INSTALLED_VER_KEYNAME" "$VECTR_RELEASE_ZIP_NAME")

    local VECTR_INSTALLED_VER_ENV_CHECK
    VECTR_INSTALLED_VER_ENV_CHECK="$(envFileKeyEqualsValue "$ENV_FILE" "$VECTR_ENV_INSTALLED_VER_KEYNAME" "$VECTR_RELEASE_ZIP_NAME")"

    printStatusMark "$VECTR_INSTALLED_VER_ENV_CHECK" 
    printf " Verify VECTR Installed version set in ENV file\n"

    chown "${ENV_VECTR_OS_USER}" "${ENV_FILE}"

    # -------------------------------------------------------------------------------------------
    # Step 23: Output docker compose command to start running VECTR
    # ------------------------------------------------------------------------------------------- 

    echo ""
    echo "-------------------- INSTALLATION COMPLETE -----------------------"
    echo " # NOTE: cd to your vectr deploy app directory (ex: cd $VECTR_APP_DIR) then run the following command:"
    echo ""
    echo "sudo docker-compose -f docker-compose.yml -f devSsl.yml -p $ENV_FILE_NAME up -d"
    echo ""
    echo " # NOTE: VECTR will take 2-5 minutes to deploy for the first time. "
    echo " #  Once deployed you may visit https://$ENV_VECTR_HOSTNAME:$ENV_VECTR_PORT"
    
}



deployVectr

SCRIPTEXIT
exit 0

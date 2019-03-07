#!/bin/bash
#
# Maintainer: David Ryder, David.Ryder@AppDynamics.com
#
# Install platform, controller, events service
#
# Commands:
#   installPlatform
#   addLocalHost
#   installController
#   installEventsService
#   showParams
#
# Requires:
#    econsole-envvars.sh
#

# Required environment variables
declare -a \
envVarList=("APPD_CONTROLLER_HOST" "APPD_CONTROLLER_PORT" \
            "APPD_CONTROLLER_INSTALL_DIR" "APPD_SSH_PRI_KEY_FILE" \
            "APPD_SSH_CREDENTIAL_NAME" "APPD_SSH_USER_NAME" "APPD_CONTROLLER_NAME" \
            "APPD_CONTROLLER_MODE" "APPD_CONTROLLER_PROFILE" "APPD_CONTROLLER_ADMIN" \
            "APPD_UNIVERSAL_PWD" "APPD_LICENSE_FILE" "APPD_EVENTSSERVICE_PROFILE")
[ -z "$APPD_VERSION" ]  && { echo "APPD_VERSION parameter not set"; exit 0; }
[ -z "$APPD_RELEASE_NUMBER" ]  && { echo "APPD_RELEASE_NUMBER parameter not set"; exit 0; }
EXIT_STATUS="1"
for evar in "${envVarList[@]}"; do
   [ -z ${!evar} ] && { echo "Environment variable not set: $evar"; EXIT_STATUS="0"; }
done
[ $EXIT_STATUS = "0" ] && { echo "Exiting"; exit 0; }


cmd=${1:-"unknown"}

#
# APPD_CURRENT_PLATFORM = APPD_CONTROLLER_NAME
#
#APPD_PLATFORM_ADMIN_CMD=$APPD_CONTROLLER_INSTALL_DIR/platform/platform-admin/bin/platform-admin.sh

#####################################
# Create a Platform
#
if [ $cmd == "installPlatform" ]; then
   $APPD_PLATFORM_ADMIN_CMD login --user-name  $APPD_CONTROLLER_ADMIN --password $APPD_UNIVERSAL_PWD

    # Create Platform
    $APPD_PLATFORM_ADMIN_CMD create-platform --name $APPD_CONTROLLER_NAME --installation-dir $APPD_CONTROLLER_INSTALL_DIR

    # Add credentials
    $APPD_PLATFORM_ADMIN_CMD add-credential \
      --credential-name $APPD_SSH_CREDENTIAL_NAME \
      --user-name $APPD_SSH_USER_NAME \
      --ssh-key-file $APPD_SSH_PRI_KEY_FILE \
      --platform-name $APPD_CONTROLLER_NAME

elif [ $cmd == "addLocalHost" ]; then
  # Add a local host, no credentials
  $APPD_PLATFORM_ADMIN_CMD add-hosts --hosts $APPD_CONTROLLER_HOST \
    --platform-name $APPD_CONTROLLER_NAME

elif [ $cmd == "addRemoteHost" ]; then
    # Add a remote host
    $APPD_PLATFORM_ADMIN_CMD add-hosts --hosts $APPD_CONTROLLER_HOST \
      --credential $APPD_SSH_CREDENTIAL_NAME \
      --platform-name $APPD_CONTROLLER_NAME

#####################################
# Install a Controller
#
elif [ $cmd == "installController" ]; then
    $APPD_PLATFORM_ADMIN_CMD login --user-name  $APPD_CONTROLLER_ADMIN --password $APPD_UNIVERSAL_PWD

    # Install controller
    $APPD_PLATFORM_ADMIN_CMD submit-job --service controller --job install --platform-name $APPD_CONTROLLER_NAME --args \
      controllerProfile=$APPD_CONTROLLER_PROFILE \
      controllerTenancyMode=$APPD_CONTROLLER_MODE \
      controllerPrimaryHost=$APPD_CONTROLLER_HOST \
      controllerAdminUsername=$APPD_CONTROLLER_ADMIN \
      controllerAdminPassword=$APPD_UNIVERSAL_PWD \
      controllerRootUserPassword=$APPD_UNIVERSAL_PWD \
      mysqlRootPassword=$APPD_UNIVERSAL_PWD

elif [ $cmd == "licenseLocal" ]; then
  cp $APPD_LICENSE_FILE $APPD_CONTROLLER_INSTALL_DIR/controller/.

elif [ $cmd == "licenseRemote" ]; then
  scp -i $APPD_SSH_PRI_KEY_FILE $APPD_LICENSE_FILE $APPD_SSH_USER_NAME@$APPD_CONTROLLER_HOST:$APPD_CONTROLLER_INSTALL_DIR/controller/.

#####################################
# Install the Events Service
#
elif [ $cmd == "installEventsService" ]; then
  # Install Events Service
  $APPD_PLATFORM_ADMIN_CMD install-events-service \
    --profile $APPD_EVENTSSERVICE_PROFILE \
    --hosts $APPD_CONTROLLER_HOST \
    --data-dir $APPD_CONTROLLER_INSTALL_DIR \
    --platform-name $APPD_CONTROLLER_NAME


    SAFE_FOR_SED="sed 's/[[\.*^$/]/\\&/g'"

    _modifyProperties() {
      echo "Updating properties $1 to $2 in $3"
      V1=$(printf '%s\n' "$1"      | sed 's/[[\.*^$/]/\\&/g'   )
      NEW_VAL=$(printf '%s\n' "$2" | sed 's/[[\.*^$/]/\\&/g'   )
      echo $V1 $NEW_VAL
      MFILE=$3
      sed -i -- 's/.*$V1.*/$V1"="$NEW_VAL/' $MFILE
    }


MFILE=$APPD_CONTROLLER_INSTALL_DIR/events-service/processor/conf/events-service-api-store.properties
_modifyProperties ad.bizoutcome.enabled      true       $MFILE
sed -i -- 's/ad\.bizoutcome\.enabled=false/ad\.bizoutcome\.enabled=true/g' $MFILE
grep ad.bizoutcome.enabled $MFILE
# events-service/processor/conf/events-service-api-store.properties
# ad.bizoutcome.enabled=true


#####################################
# Install a Controller
#
elif [ $cmd == "deletePlatform" ]; then
      # Install controller
      $APPD_PLATFORM_ADMIN_CMD login --user-name  $APPD_CONTROLLER_ADMIN --password $APPD_UNIVERSAL_PWD
      $APPD_PLATFORM_ADMIN_CMD list-platforms
      $APPD_PLATFORM_ADMIN_CMD remove-hosts --hosts $APPD_CONTROLLER_HOST --platform-name $APPD_CONTROLLER_NAME
      $APPD_PLATFORM_ADMIN_CMD remove-dead-hosts --hosts $APPD_CONTROLLER_HOST --platform-name $APPD_CONTROLLER_NAME
      $APPD_PLATFORM_ADMIN_CMD list-credentials --platform-name $APPD_CONTROLLER_NAME
      $APPD_PLATFORM_ADMIN_CMD remove-credential --credential-name $APPD_SSH_CREDENTIAL_NAME --platform-name $APPD_CONTROLLER_NAME
      $APPD_PLATFORM_ADMIN_CMD delete-platform --name $APPD_CONTROLLER_NAME

#####################################
# Get the controller status
#
elif [ $cmd == "controllerStatus" ]; then
    # Controller status
    curl $APPD_CONTROLLER_HOST:$APPD_CONTROLLER_PORT/controller/rest/serverstatus

elif [ $cmd == "showParams" ]; then
  $APPD_PLATFORM_ADMIN_CMD list-job-parameters --job install --service controller
  $APPD_PLATFORM_ADMIN_CMD list-job-parameters --job install --service events-service

elif [ $cmd == "createResponseFile" ]; then
  RFILE=${2:-"/tmp/appd-econsole-response.varfile"}
  echo "Creating "$RFILE
  echo "# Automatically generated "                                 > $RFILE
  echo "serverHostName=$APPD_CONTROLLER_HOST"                       >> $RFILE
  echo "sys.languageId=en"                                          >> $RFILE
  echo "disableEULA=true"                                           >> $RFILE
  echo "sys.installationDir=$APPD_CONTROLLER_INSTALL_DIR/platform"  >> $RFILE
  echo "platformAdmin.dataDir=$APPD_CONTROLLER_INSTALL_DIR/platform/mysql/data" >> $RFILE
  echo "platformAdmin.databasePort=3377"                            >> $RFILE
  echo "platformAdmin.databasePassword=$APPD_UNIVERSAL_PWD"         >> $RFILE
  echo "platformAdmin.databaseRootPassword=$APPD_UNIVERSAL_PWD"     >> $RFILE
  echo "platformAdmin.adminPassword=$APPD_UNIVERSAL_PWD"            >> $RFILE
  echo "platformAdmin.useHttps$Boolean=false"                       >> $RFILE

else
  echo "Command unknown: "$cmd
  echo "Commands: "
  echo "installPlatform"
  echo "addLocalHost"
  echo "addRemoteHost"
  echo "installController"
  echo "installEventsService"
  echo "deletePlatform"
  echo "controllerStatus"

fi

# Complete
# $APPD_PLATFORM_ADMIN_CMD delete-platform --name c2

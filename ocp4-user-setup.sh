#!/bin/bash
#
#*******************************************************************************
#  NOTE THAT THIS SCRIPT IS INTENDED FOR OPENSHIFT CONTAINER PLATFORM 4 TEST
#      ENVIRONMENTS ONLY. THE SCRIPT MAKES CHANGES TO OAUTH IDENTITY
#  PROVIDER CONFIGURATION AND OPENSHIFT USER ACCOUNTS. REVIEW THIS SCRIPT
#      THOROUGHLY TO DETERMINE SUITABILITY FOR YOUR TEST ENVIRONMENT
#*******************************************************************************
#
# This script automates user setup for newly deployed OpenShift Container Platform 4 test clusters. The script does the following:
#
# * Configures HTPasswd identity provider, creates a secret and creates 'admin' and 'developer' users
# * Applies roles to those users

TMP=$(mktemp -d)

function notice ()
{
echo "*******************************************************************************
  NOTE THAT THIS SCRIPT IS INTENDED FOR OPENSHIFT CONTAINER PLATFORM 4 TEST
      ENVIRONMENTS ONLY. THE SCRIPT MAKES CHANGES TO OAUTH IDENTITY
  PROVIDER CONFIGURATION AND OPENSHIFT USER ACCOUNTS. REVIEW THIS SCRIPT
      THOROUGHLY TO DETERMINE SUITABILITY FOR YOUR TEST ENVIRONMENT
*******************************************************************************"
while true; do
  read -rp "Do you want to continue? (y/n): " YESNO
  case $YESNO in
      y ) break;;
      n ) echo "Exiting."; exit 0;;
      * ) echo "Please answer 'y' or 'n':";;
  esac
done
echo
}

function kubeadmin_login ()
{
echo "Log into your cluster initially as kubeadmin:"; echo

# Request cluster API endpoint and kubeadmin token from user:
read -rp "- Enter cluster API endpoint and port (i.e. https://api.<cluster_name>.<sub_domain>.<domain>:<port>: " APIURL
echo
unset -v KUBEPW # Make sure the $KUBEPW password variable is not exported
set +o allexport  # Make sure variables are not automatically exported
read -rs -p "- Enter kubeadmin token (this will not be echoed to the console and the variable will not be exported): " KUBEPW < /dev/tty &&
echo

# Log in as kubeadmin:
oc login --token="${KUBEPW[0]}" --server="${APIURL[0]}"
RESULT=$?
if [[ "${RESULT}" != "0" ]]; then
  echo "Login unsuccessful. Exiting."
  exit 0
else
  OCPUSER=$(oc whoami)
  echo "Now logged in as ${OCPUSER}."
fi
echo
}

function create_users ()
{
echo "### Configuring HTPasswd IP, create secret and users ###"
# Create an HTPasswd file called `${TMP}/htpasswd_file` if it does not already exist and add new users. If the file does already exist, then add/update users. These users will later be assigned different monitoring roles:
if [[ -f "${TMP}/htpasswd_file" ]]; then
  htpasswd -b "${TMP}/htpasswd_file" admin Passwd01
else
  htpasswd -c -B -b "${TMP}/htpasswd_file" admin Passwd01
fi
htpasswd -b "${TMP}/htpasswd_file" developer Passwd01
echo "Test users 'admin' and 'developer' have been allocated the password 'Passwd01'. Please change accordingly using 'htpasswd -b "${TMP}/htpasswd_file" <user_name> <password>' after this script completes."

# Create a secret resource called `localusers` from the `${TMP}/htpasswd_file` file. If a `localusers` secret already exists, ask for user confirmation before deleting and recreating:
SECRETNAME=$(oc get secrets -n openshift-config | grep -is 'localusers' | awk '{print $1}')
if [[ "${SECRETNAME}" = "localusers" ]]; then
  while true; do
    read -rp "secret/localusers already exists in the openshift-config namespace. Delete it and create a new secret to include the users defined above? (y/n): " YESNO
    case $YESNO in
        y )
          oc delete secret/localusers -n openshift-config
          oc create secret generic localusers --from-file htpasswd="${TMP}/htpasswd_file" -n openshift-config
          break
          ;;
        n )
          echo "Users required by this script might not exist in current secret/localusers resource. Exiting."
          exit 0
          ;;
        * )
          echo "Please answer 'y' or 'n':"
          ;;
    esac
  done
else
  oc create secret generic localusers --from-file htpasswd="${TMP}/htpasswd_file" -n openshift-config
fi

# Update the `cluster` oauth configuration to enable an `htpasswd` identity provider which references the `localusers` secret. Once the updated configuration is saved, the HTPasswd users will be able to authenticate into the cluster:
oc get oauths.config.openshift.io cluster -n openshift-authentication -o yaml | grep -v '^spec:' > "${TMP}/oauth.yaml"
cat <<EOF >> "${TMP}/oauth.yaml"
spec:
  identityProviders:
  - htpasswd:
      fileData:
        name: localusers
    mappingMethod: claim
    name: myusers
    type: HTPasswd
EOF

# Apply the `${TMP}/oauth.yaml` configuration to the cluster:
oc apply -f "${TMP}/oauth.yaml"

# Wait some time while the oauth-openshift-* Pods restart, applying the new configuration:
echo "Waiting for oauth Pods to restart..."
sleep 60
oc get pods -n openshift-authentication
echo
}

function apply_roles ()
{
echo "################### Applying roles #####################"
# Provide a message about upcoming "Warning: User '<user>' not found" warnings:
echo "You can ignore 'Warning: User '<user>' not found' warning messages which may appear shortly..."

# Assign the `admin` user the `cluster-admin` role:
oc adm policy add-cluster-role-to-user cluster-admin admin
echo
}

function login_commands ()
{
echo "################### Login commands ####################"
# Provide a message detailing how to log in as the newly created users:
echo "You can now log in as 'admin' or 'developer' users in this test environment, using the following commands:"; echo
echo "oc login -u admin -p Passwd01 --server=${APIURL[0]}"
echo "oc login -u developer -p Passwd01 --server=${APIURL[0]}"; echo
echo "To change user passwords, first update the htpasswd file:"; echo
echo "htpasswd -b "${TMP}/htpasswd_file" <user_name> <password>"; echo
echo "Then, update the secret. You need 'cluster-admin' privileges to run the following:"; echo
echo "oc create secret generic localusers --from-file htpasswd="${TMP}/htpasswd_file" --dry-run -o yaml | oc replace -n openshift-config -f -"; echo
echo "The updated credentials will become active after the oauth Pods restart. The Pod restarts might take a few moments."
echo
}

# Main:
notice
kubeadmin_login
create_users
apply_roles
login_commands

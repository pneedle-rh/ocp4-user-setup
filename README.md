# OpenShift 4 user setup script for test environments

_This script is intended for OpenShift Container Platform 4 test environments only. The script makes changes to `oauth` identity provider configuration and OpenShift user accounts. Review this script thoroughly to determine suitability for your test environment._

The script automates user setup for newly deployed OpenShift Container Platform 4 test clusters by doing the following:

* Configuring a local HTPasswd-based identity provider
* Creating an identity secret associated with that identity provider
* Creating `admin` and `developer` users
* Assigning the `admin` user the `cluster-admin` role

Apply the following permissions to make the script executable:

~~~
$ chmod 755
~~~

Run the script as follows:

~~~~
$ ./ocp4-user-setup.sh
~~~~

Once the script has completed successfully, you can then log in as `admin` or `developer` users, by using the following commands:

~~~
oc login -u admin -p Passwd01 --server=https://api.pneedleocp45.lab.upshift.rdu2.redhat.com:6443
~~~

~~~
oc login -u developer -p Passwd01 --server=https://api.pneedleocp45.lab.upshift.rdu2.redhat.com:6443
~~~

To change user passwords after the script has completed, first update the HTPasswd file. Replace `<temp_dir>` with the directory name that is included in the script's output:

~~~
htpasswd -b /tmp/<temp_dir>/htpasswd_file <user_name> <password>
~~~

After updating the htpasswd file, you need to update the secret for credential changes to become active. You need `cluster-admin` privileges to run the following:

~~~
oc create secret generic localusers --from-file htpasswd=/tmp/tmp.GyRtiZJhPd/htpasswd_file --dry-run -o yaml | oc replace -n openshift-config -f -
~~~

This restarts `oauth` Pods, which might take a few moments. The credential updates become active after the Pods have restarted.

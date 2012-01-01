Devstack is a set of scripts and utilities to quickly deploy an OpenStack cloud.

# Goals

* To quickly build dev OpenStack environments in a clean oneiric environment
* To describe working configurations of OpenStack (which code branches work together?  what do config files look like for those branches?)
* To make it easier for developers to dive into OpenStack so that they can productively contribute without having to understand every part of the system at once
* To make it easy to prototype cross-project features

Read more at http://devstack.org (built from the gh-pages branch)

IMPORTANT: Be sure to carefully read stack.sh and any other scripts you execute before you run them, as they install software and may alter your networking configuration.  We strongly recommend that you run stack.sh in a clean and disposable vm when you are first getting started.

# Versions

The devstack master branch generally points to trunk versions of OpenStack components.  For older, stable versions, look for branches named stable/[mil
estone].  For example, you can do the following to create a diablo OpenStack cloud:

    git checkout stable/diablo
    ./stack.sh

# To start a dev cloud (Installing in a dedicated, disposable vm is safer than installing on your dev machine!):

    ./stack.sh

When the script finishes executing, you should be able to access OpenStack endpoints, like so:

* Horizon: http://myhost/
* Keystone: http://myhost:5000/v2.0/

We also provide an environment file that you can use to interact with your cloud via CLI:

    # source openrc file to load your environment with osapi and ec2 creds
    . openrc
    # list instances
    nova list
    # list instances using ec2 api
    euca-describe-instances

# Customizing

You can override environment variables used in stack.sh by creating file name 'localrc'.  It is likely that you will need to do this to tweak your networking configuration should you need to access your cloud from a different host.

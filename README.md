# Bosh Deploy

Bosh deploy is a simple script that automates discovery of your IaaS environments and generates manifest files that can be used to:

1. Create a *microbosh* environment using [bosh-init](https://github.com/cloudfoundry/bosh-init).
2. Deploy Bosh releases to the IaaS environment via the microbosh created in 1.

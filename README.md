<a href="https://minaprotocol.com">
	<img width="200" src="https://minaprotocol.com/static/Mina_Wordmark_Github.png" alt="Mina Logo" />
</a>
<hr/>

# Repository Purpose

This repository is designed to show an opinionated example on how to operate a network of Coda Daemons. It implements the entire node lifecycle using a modern Infrastructure as Code toolset. Community contributions are warmly encouraged, please see the [contribution guidelines](#to-do) for more details. The code is designed to be as modular as possible, allowing the end-user to "pick and choose" the parts they would like to incorporate into their own infrastructure stack.

If you have any issues setting up your testnet or have any other questions about this repository, join the public [Discord Server](https://discord.gg/ShKhA7J) and get help from the Coda community.

# Code Structure

```
coda-automation
├── helm
│   ├── block-producer
│   └── snark-worker
├── scripts
├── services
└── terraform
    ├── infrastructure
    ├── modules
    └── testnets
```

**Helm:** Contains Helm Charts for various components of a Coda Testnet

- _block-producer:_ One or more block producers consisting of unique `deployments`
- _snark-worker:_ Deploys a "SNARK Coordinator" consisting of one or more worker process containers

**Terraform:** Contains resource modules and live code to deploy a Coda Testnet.

- Note: Currently most modules are written against Google Kubernetes Engine, multi-cloud support is on the roadmap.
- _infrastructure:_ The root module for infrastructure like K8s Clusters and Prometheus.
- _kubernetes/testnet:_ A Terraform module that encapsulates a Coda Testnet, including Seed Nodes, Block Producers and SNARK Workers.
- _google-cloud/coda-seed-node:_ A Terraform module that deploys a set of public Seed Nodes on Google Compute Engine in the configured region.
  _Scripts:_ Testnet utilities for key generation & storage, redelegation, etc.

# Prerequisites

For the purposes of this README we are assuming the following:

- You have a configured AWS Account with credentials on your machine: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html
- You have a configured Google Cloud Project with credentials on your machine: https://cloud.google.com/sdk/gcloud/reference/auth/login
- You have Terraform `0.12.28` installed on your machine

  MacOS:
  `brew install terraform@v0.12.28`

  Other Platforms: https://www.terraform.io/downloads.html

- You have Kubectl configured for the GKE cluster of your choice: https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl
  TL;DR: `gcloud container clusters get-credentials -region us-east1 coda-infra-east`

# What is a Testnet

A Testnet (a.k.a. Test Network) is a tool that is used to "test" Coda's distributed software. Our testnets are designed to simulate a "Mainnet" environment in order to identify bugs and test new functionality. Along with the network itself, there are several bots and services that are additionally deployed to facilitate a baseline of activity and access to the network.

# Components of a Testnet

### Whale and Fish Block Producers

In order to simulate a differentiation between O(1) Stake (Whales) and end-user stake (Fish), the testnets adhere to a simple naming scheme to differentiate between the two. In order to facilitate this, additional configuration must be made in the ledger, allocating a large amount of stake to "Whale Block Producers" and a lesser amount to "Fish Block Producers".

### Bots

Bots are often used to automate transactions being sent around the network. Often, these require special consideration in the genesis ledger, so it's worth keeping them in mind when setting up a new network. For example, the O(1) Discord Faucet is a simple sidecar bot that runs against a Coda Daemon's GraphQL Port and responds to requests for funds in the Coda Protocol Discord server.

### Services

Like bots, there are other blockchain-aware services that are deployed but might not need special consideration or stake. Two good examples of this are the Archive Node and the GraphQL Proxy.

### Ledger

The ledger is arguably the most important thing to get right, because this single point of failure can bork an entire deployment. There are several key points that have to be configured correctly for a network to bootstrap as expected:

- Offline keys delegated to online keys
- Proper balances and currency encoding
- Proper formatting of ledger itself

## QA Testnet

QA Testnets are designed to be run internally to support feature development and bug triage. Seed nodes are launched in Kubernetes with cluster-local DNS.

## Public Testnet

Public Testnets are functionally similar to QA Testnets but have the addition of "public" seed nodes with static IP addresses. This is required due to the necessarily dynamic nature of Kubernetes, so these public seeds are launched via Google Compute Engine VMs.

# Deploy a QA Testnet

Deployng a testnet is a relatively straightforward process once you have ironed out the configuration. At a high level, there are several pieces of configuration it's important to keep in mind or else your deployment might fail:

- Coda Keypairs
- Genesis Ledger
- Runtime Constants

### Clone the Repository

(If you are reading this locally, good job!)

### Apply the Infrastructure Module (If deploying infrastructure completely from scratch)

Most developers shouldn't have to worry about this, however it's worth noting that the entire infrastructure can be deployed from scratch by running `terraform init && terraform apply` in `terraform/infrastructure`.

If you don't know if you _should_ do this, you probably shouldn't!

### Generate Keys

Currently, keys are managed by `scripts/testnet-keys.py`, you need to generate keys for each role and/or service you intend to deploy.

The following is a series of example commands you might run to generate keys for a small network:

```
python3 scripts/testnet-keys.py keys  generate-offline-fish-keys --count 25
python3 scripts/testnet-keys.py keys  generate-online-fish-keys --count 25
python3 scripts/testnet-keys.py keys  generate-offline-whale-keys --count 5
python3 scripts/testnet-keys.py keys  generate-online-whale-keys --count 5
python3 scripts/testnet-keys.py keys  generate-service-keys //(optional)
```

These commands will generate folders in the `scripts` directory by default, this output directory is a configurable location.

```
$ python3 scripts/testnet-keys.py keys generate-offline-fish-keys --help
Usage: testnet-keys.py keys generate-offline-fish-keys [OPTIONS]

  Generate Public Keys for Offline Fish Accounts

Options:
  --count INTEGER      Number of Fish Account keys to generate.
  --output-dir TEXT    Directory to output Fish Account Keys to.
  --privkey-pass TEXT  The password to use when generating keys.
  --help               Show this message and exit.
```

### Generate Genesis Ledger

Once you have the keys for your deploymenet created, you can use them to generate a genesis ledger with the following command.

```
python3 scripts/testnet-keys.py ledger generate-ledger
```

The script will try to load keys from the default directories here, so if you wrote them to a different spot (or moved them), you can pass the location via the CLI.

```
$ python3 scripts/testnet-keys.py ledger generate-ledger --help
Usage: testnet-keys.py ledger generate-ledger [OPTIONS]

  Generates a Genesis Ledger based on previously generated Whale, Fish, and
  Block Producer keys.  If keys are not present on the filesystem at the
  specified location, they are not generated.

Options:
  --generate-remainder TEXT       Indicates that keys should be generated if
                                  there are not a sufficient number of keys
                                  present.
  --service-accounts-directory TEXT
                                  Directory where Service Account Keys will be
                                  stored.
  --num-whale-accounts INTEGER    Number of Whale accounts to be generated.
  --online-whale-accounts-directory TEXT
                                  Directory where Offline Whale Account Keys
                                  will be stored.
  --offline-whale-accounts-directory TEXT
                                  Directory where Offline Whale Account Keys
                                  will be stored.
  --num-fish-accounts INTEGER     Number of Fish accounts to be generated.
  --online-fish-accounts-directory TEXT
                                  Directory where Online Fish Account Keys
                                  will be stored.
  --offline-fish-accounts-directory TEXT
                                  Directory where Offline Fish Account Keys
                                  will be stored.
  --staker-csv-file TEXT          Location of a CSV file detailing Discord
                                  Username and Public Key for Stakers.
  --help                          Show this message and exit.
```

There's several gotchas here that the script will check for:

- For a particular block producer "class", number of offline and online keys must be equal
- Remember the path to the ledger file here, you will need it as an input to your deployment

### Create a Testnet

Next, you must create a new testnet in `terraform/testnets/`. For ease of use, you can copy-paste an existing one, however it's important to go through the terraform and change the following things:

- location of Terraform state file
- Name of testnet
- number of nodes to deploy
- Location of the Genesis Ledger

### Autodeploy.sh

Assuming the hard task of configuration has been completed without error, this script will make your deployment experience a _breeze_.

This script will do the following:

- Attempt to tear down (aka "destroy") the existing testnet, should it exist
- Deploy anew the testnet as defined in the previous section
- Upload the keys you generated to Kubernetes as Secrets for use at runtime

Note: The deployment of keys relies on kubectl being properly configured for the cluster you are deploying to!

```
./scripts/auto-deploy.sh <testnet>
```

### Is it Working?

#### Logs

Logs will be persisted in StackDriver for any container deployment.

**Example Queries:**

Get all logs from `fish-block-producer-1` in the `<testnet>` namespace.

```
resource.type="k8s_container"
resource.labels.project_id="o1labs-192920"
resource.labels.location="us-east1"
resource.labels.cluster_name="coda-infra-east"
resource.labels.namespace_name="<testnet>"
labels.k8s-pod/app="fish-block-producer-1"
```

Get all logs from any Block Producer (note the `:` instead of `=` in `labels.k8s-pod/app:"block-producer"`!):

```
resource.type="k8s_container"
resource.labels.project_id="o1labs-192920"
resource.labels.location="us-east1"
resource.labels.cluster_name="coda-infra-east"
resource.labels.namespace_name="<testnet>"
labels.k8s-pod/app:"block-producer"
```

#### Dashboards

There are several public Grafana dashboards available here:

- [Network Overview](https://o1testnet.grafana.net/d/qx4y6dfWz/network-overview?orgId=1)
- [Block Producer](https://o1testnet.grafana.net/d/Rgo87HhWz/block-producer-dashboard?orgId=1&refresh=1m)
- [SNARK Worker](https://o1testnet.grafana.net/d/scQUGOhWk/snark-worker-dashboard?orgId=1&refresh=1m)

# Deploy a Public Testnet

### Bkase's memory of deploys as of 9/16

0. Commit to master
1. git tag 0.0.16-beta4 (with -m or it won't work) (increment the 4 every time)
2. push the tag
3. Push the master
4. curl -X POST --header "Content-Type: application/json" -H "Circle-Token: 62bcf7b6c8ef60bdee3ecb3618d530e5f77eb78e" -d '{ "branch": "master", "parameters": { "run-ci": true } }' 'https://circleci.com/api/v2/project/github/CodaProtocol/coda/pipeline'
   (this starts the build)
5. In coda automation, unzip the 3.3-keys.tar.gz into coda-automation
6. Download secrets for gogoel cloud storage -- scripts/o1-google-cloud-storage-api-key.json
7. Download secrets for faucet API token -- scripts/o1-discord-api-key
8. In coda automation, checkout test-public-testnet-deploy branch
9. This deployment is located in pickles/ testnet
10. Run `./scripts/auto-deploy.sh pickles keys/`

### Collect User Key Submissions

The purpose of a public testnet is to allow end-users to try out the software and learn how to operate it. Thus, we accept sign-ups for stake to be allocated in the genesis, and commit those keys to the compiled genesis ledger.

For context, these keys correspond to the "Fish Keys" in the QA Net deployments, and Online Fish Keys are ommitted in a Public Testnet deployment and "Offline Fish Keys" are instead delegated to the submitted User Keys.

### Generate Keys

As in a QA Network, keys are managed by `scripts/testnet-keys.py`, you need to generate keys for each role and/or service you intend to deploy.

In the case of a public testnet, the following commands could be run:

```
python3 scripts/testnet-keys.py keys  generate-offline-fish-keys --count <nUserSubmissions>
python3 scripts/testnet-keys.py keys  generate-offline-whale-keys --count 5
python3 scripts/testnet-keys.py keys  generate-online-whale-keys --count 5
python3 scripts/testnet-keys.py keys  generate-service-keys //(faucet, echo, etc...)
```

These commands will generate folders in the `scripts` directory by default, this output directory is a configurable location.

```
$ python3 scripts/testnet-keys.py keys generate-offline-fish-keys --help
Usage: testnet-keys.py keys generate-offline-fish-keys [OPTIONS]

  Generate Public Keys for Offline Fish Accounts

Options:
  --count INTEGER      Number of Fish Account keys to generate.
  --output-dir TEXT    Directory to output Fish Account Keys to.
  --privkey-pass TEXT  The password to use when generating keys.
  --help               Show this message and exit.
```

### Generate Genesis Ledger

Once you have the keys for your deploymenet created, and the Staker Keys saved to a CSV, you can use them to generate a genesis ledger with the following command.

```
python3 scripts/testnet-keys.py ledger generate-ledger
```

The script will try to load keys from the default directories here, so if you wrote them to a different spot (or moved them), you can pass the location via the CLI.

```
$ python3 scripts/testnet-keys.py ledger generate-ledger --help
Usage: testnet-keys.py ledger generate-ledger [OPTIONS]

  Generates a Genesis Ledger based on previously generated Whale, Fish, and
  Block Producer keys.  If keys are not present on the filesystem at the
  specified location, they are not generated.

Options:
  --generate-remainder TEXT       Indicates that keys should be generated if
                                  there are not a sufficient number of keys
                                  present.
  --service-accounts-directory TEXT
                                  Directory where Service Account Keys will be
                                  stored.
  --num-whale-accounts INTEGER    Number of Whale accounts to be generated.
  --online-whale-accounts-directory TEXT
                                  Directory where Offline Whale Account Keys
                                  will be stored.
  --offline-whale-accounts-directory TEXT
                                  Directory where Offline Whale Account Keys
                                  will be stored.
  --num-fish-accounts INTEGER     Number of Fish accounts to be generated.
  --online-fish-accounts-directory TEXT
                                  Directory where Online Fish Account Keys
                                  will be stored.
  --offline-fish-accounts-directory TEXT
                                  Directory where Offline Fish Account Keys
                                  will be stored.
  --staker-csv-file TEXT          Location of a CSV file detailing Discord
                                  Username and Public Key for Stakers.
  --help                          Show this message and exit.
```

There's several gotchas here that the script will check for:

- For a particular block producer "class", number of offline and online keys must be equal
- Remember the path to the ledger file here, you will need it as an input to your deployment

### Create a Testnet

Next, you must create a new testnet in `terraform/testnets/`. For ease of use, you can copy-paste an existing one, however it's important to go through the terraform and change the following things:

- location of Terraform state file
- Name of testnet
- number of nodes to deploy
- Location of the Genesis Ledger

In addition, you must include one or more public seed nodes for users to bootstrap with:

```
module "network" {
  source         = "../../modules/google-cloud/vpc-network"
  network_name   = "${local.netname}-testnet-network"
  network_region = "us-west1"
  subnet_name    = "${local.netname}-testnet-subnet"
}

module "seed_one" {
  source             = "../../modules/google-cloud/coda-seed-node"
  coda_image         = local.coda_image
  project_id         = data.google_project.project.project_id
  subnetwork_project = data.google_project.project.project_id
  subnetwork         = module.network.subnet_link
  network            = module.network.network_link
  instance_name      = "${local.netname}-seed-one"
  zone               = "us-west1-a"
  region             = "us-west1"
  client_email       = "1020762690228-compute@developer.gserviceaccount.com"
  discovery_keypair  = "23jhTeLbLKJSM9f3xgbG1M6QRHJksFtjP9VUNUmQ9fq3urSovGVS25k8LLn8mgdyKcYDSteRcdZiNvXXXAvCUnST6oufs,4XTTMESM7AkSo5yfxJFBpLr65wdVt8dfuQTuhgQgtnADryQwP,12D3KooWP7fTKbyiUcYJGajQDpCFo2rDexgTHFJTxCH8jvcL1eAH"
  seed_peers         = ""
}

module "seed_two" {
  source             = "../../modules/google-cloud/coda-seed-node"
  coda_image         = local.coda_image
  project_id         = data.google_project.project.project_id
  subnetwork_project = data.google_project.project.project_id
  subnetwork         = module.network.subnet_link
  network            = module.network.network_link
  instance_name      = "${local.netname}-seed-two"
  zone               = "us-west1-a"
  region             = "us-west1"
  client_email       = "1020762690228-compute@developer.gserviceaccount.com"
  discovery_keypair  = "23jhTbijdCA9zioRbv7HboRs7F8qZL59N5GQvGzhfB3MrS5qNrQK5fEdWyB5wno9srsDFNRc4FaNUDCEnzJGHG9XX6iSe,4XTTMBUfbSrzTGiKVp8mhZCuE9nDwj3USx3WL2YmFpP4zM2DG,12D3KooWL9ywbiXNfMBqnUKHSB1Q1BaHFNUzppu6JLMVn9TTPFSA"
  seed_peers         = "-peer /ip4/${module.seed_one.instance_external_ip}/tcp/10002/p2p/12D3KooWP7fTKbyiUcYJGajQDpCFo2rDexgTHFJTxCH8jvcL1eAH"
}

# Seed DNS
data "aws_route53_zone" "selected" {
  name = "o1test.net."
}

resource "aws_route53_record" "seed_one" {
  zone_id = "${data.aws_route53_zone.selected.zone_id}"
  name    = "seed-one.${local.netname}.${data.aws_route53_zone.selected.name}"
  type    = "A"
  ttl     = "300"
  records = [module.seed_one.instance_external_ip]
}

resource "aws_route53_record" "seed_two" {
  zone_id = "${data.aws_route53_zone.selected.zone_id}"
  name    = "seed-two.${local.netname}.${data.aws_route53_zone.selected.name}"
  type    = "A"
  ttl     = "300"
  records = [module.seed_two.instance_external_ip]
}
```

### Autodeploy.sh

Assuming the hard task of configuration has been completed without error, this script will make your deployment experience a _breeze_.

This script will do the following:

- Attempt to tear down (aka "destroy") the existing testnet, should it exist
- Deploy anew the testnet as defined in the previous section
- Upload the online keys you generated to Kubernetes as Secrets for use at runtime

Note: The deployment of keys relies on kubectl being properly configured for the cluster you are deploying to!

```
./scripts/auto-deploy.sh <testnet>
```

# Testnet SDK

We've included a utility tool to help with the process of spinning up a network. To use the tool clone the repo and run the following commands:

```
yarn
yarn build
yarn link
```

Now you can use the `coda-network` command. To use some of the functionality, you'll need a [Google Cloud Service Account](https://cloud.google.com/iam/docs/service-accounts). Once you download the key for the service account, use the following command to configure it:

```
export GOOGLE_APPLICATION_CREDENTIALS=<PATH_TO_KEYFILE>
```

Try the following command to get started:

```
coda-network --help
```

Some of the common commands are:

```
coda-network keypair create
coda-netowrk keyset create -n <KEYSET_NAME>
coda-network keyset add -n <KEYSET_NAME> -k <PUBLIC_KEY>
coda-network genesis create
```

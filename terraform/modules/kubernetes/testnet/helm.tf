provider helm {
  debug = true
  kubernetes {
    host                   = "https://${data.google_container_cluster.cluster.endpoint}"
    client_certificate     = base64decode(data.google_container_cluster.cluster.master_auth[0].client_certificate)
    client_key             = base64decode(data.google_container_cluster.cluster.master_auth[0].client_key)
    cluster_ca_certificate = base64decode(data.google_container_cluster.cluster.master_auth[0].cluster_ca_certificate)
    token                  = data.google_client_config.current.access_token
    load_config_file       = false
  }
}

# data "helm_repository" "coda_helm_repo" {
#   name = "coda-helm-repo"
#   url  = var.coda_helm_repo
# }

locals {
  mina_helm_repo = "https://coda-charts.storage.googleapis.com"

  seed_peers = [
    "/dns4/seed-node.${var.testnet_name}/tcp/10001/p2p/${split(",", var.seed_discovery_keypairs[0])[2]}"
  ]

  coda_vars = {
    runtimeConfig      = var.runtime_config
    image              = var.coda_image
    privkeyPass        = var.block_producer_key_pass
    seedPeers          = concat(var.additional_seed_peers, local.seed_peers)
    logLevel           = var.log_level
    logReceivedBlocks  = var.log_received_blocks
    logSnarkWorkGossip = var.log_snark_work_gossip
  }

  seed_vars = {
    testnetName = var.testnet_name
    coda        = local.coda_vars
    seed        = {
      active = true
      discovery_keypair = var.seed_discovery_keypairs[0]
    }
  }

  block_producer_vars = {
    testnetName = var.testnet_name

    coda = local.coda_vars

    userAgent = {
      image         = var.coda_agent_image
      minFee        = var.agent_min_fee
      maxFee        = var.agent_max_fee
      minTx         = var.agent_min_tx
      maxTx         = var.agent_max_tx
      txBatchSize   = var.agent_tx_batch_size
      sendEveryMins = var.agent_send_every_mins
    }

    bots = {
      image  = var.coda_bots_image
      faucet = {
        amount = var.coda_faucet_amount
        fee    = var.coda_faucet_fee
      }
    }

    blockProducerConfigs = [
      for index, config in var.block_producer_configs: {
        name                 = config.name
        class                = config.class
        externalPort         = var.block_producer_starting_host_port + index
        runWithUserAgent     = config.run_with_user_agent
        runWithBots          = config.run_with_bots
        enableGossipFlooding = config.enable_gossip_flooding
        privateKeySecret     = config.private_key_secret
        enablePeerExchange   = config.enable_peer_exchange
        isolated             = config.isolated
      }
    ]
  }
  
  snark_worker_vars = {
    testnetName = var.testnet_name
    coda = local.coda_vars 
    worker = {
      active = true
      numReplicas = var.snark_worker_replicas
    }
    coordinator = {
      active = true
      deployService = true
      publicKey   = var.snark_worker_public_key
      snarkFee    = var.snark_worker_fee
      hostPort    = var.snark_worker_host_port
    }
  }

  archive_node_vars = {
    testnetName = var.testnet_name
    coda = {
      image         = var.coda_image
      seedPeers     = concat(var.additional_seed_peers, local.seed_peers)
      runtimeConfig = local.coda_vars.runtimeConfig
    }
    archive = {
      image = var.coda_archive_image
      remoteSchemaFile = var.mina_archive_schema
   }
  }
  
}

# Cluster-Local Seed Node

resource "kubernetes_role_binding" "helm_release" {
  metadata {
    name      = "admin-role"
    namespace = kubernetes_namespace.testnet_namespace.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = kubernetes_namespace.testnet_namespace.metadata[0].name
  }
}

resource "helm_release" "seed" {
  name        = "${var.testnet_name}-seed"
  repository  = local.mina_helm_repo
  chart       = "seed-node"
  version     = "0.1.4"
  namespace   = kubernetes_namespace.testnet_namespace.metadata[0].name
  values = [
    yamlencode(local.seed_vars)
  ]
  wait        = true
  depends_on  = [kubernetes_role_binding.helm_release, var.gcloud_seeds]
}


# Block Producers

resource "helm_release" "block_producers" {
  name        = "${var.testnet_name}-block-producers"
  repository  = local.mina_helm_repo
  chart       = "block-producer"
  version     = "0.1.11"
  namespace   = kubernetes_namespace.testnet_namespace.metadata[0].name
  values = [
    yamlencode(local.block_producer_vars)
  ]
  wait        = false
  depends_on  = [helm_release.seed]
}

# Snark Workers 

resource "helm_release" "snark_workers" {
  name        = "${var.testnet_name}-snark-worker"
  repository  = local.mina_helm_repo
  chart       = "snark-worker"
  version     = "0.1.7"
  namespace   = kubernetes_namespace.testnet_namespace.metadata[0].name
  values = [
    yamlencode(local.snark_worker_vars)
  ]
  wait        = false
  depends_on  = [helm_release.seed]
}

resource "helm_release" "archive_node" {
  count      = var.deploy_archive ? 1 : 0
  
  name       = "${var.testnet_name}-archive-node"
  repository = local.mina_helm_repo
  chart      = "archive-node"
  version    = "0.1.3"
  namespace  = kubernetes_namespace.testnet_namespace.metadata[0].name
  values     = [
    yamlencode(local.archive_node_vars)
  ]
  wait = false
  depends_on = [helm_release.seed]
}

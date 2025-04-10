
# Infrastructure for Managed Service for OpenSearch cluster, Managed Service for Greenplum cluster, and Data Transfer.

# RU: https://cloud.yandex.ru/ru/docs/data-transfer/tutorials/opensearch-to-greenplum
# EN: https://cloud.yandex.com/en/docs/data-transfer/tutorials/opensearch-to-greenplum

# Specify the following settings:
locals {
  # The following settings are to be specified by the user. Change them as you wish.

  # Settings for the Managed Service for OpenSearch cluster:
  source_admin_password = "" # Password of user in Managed Service for OpenSearch
  mos_cluster_name      = "" # Name of the Managed Service for OpenSearch cluster

  # Settings for the Managed Service for Greenplum cluster:  
  mgp_cluster_name  = "" # Name of the Managed Service for Greenplum cluster
  mgp_username      = "" # Name of the Managed Service for Greenplum user
  mgp_user_password = "" # Password of the Managed Service for Greenplum user

  # Settings for the Data Transfer
  transfer_name = "" # Name of the Data Transfer

  # Setting for the YC CLI that allows running CLI command to activate cluster
  profile_name = "" # Name of the YC CLI profile

  # Specify these settings ONLY AFTER the clusters are created. Then run "terraform apply" command again.
  # You should set up endpoints using the GUI to obtain their IDs
  source_endpoint_id = "" # Source endpoint ID
  target_endpoint_id = "" # Target endpoint ID
  transfer_enabled   = 0  # Set to 1 to enable creation of data transfer.

  # The following settings are predefined. Change them only if necessary.

  # Network and Safety Group settings:
  network_name    = "mynet"      # Name of the network for Managed Service for OpenSearch cluster and Managed Service for Greenplum cluster
  subnet_name     = "mysubnet"   # Name of the subnet for Managed Service for OpenSearch cluster and Managed Service for Greenplum cluster
  sg_name         = "mos-mgp-sg" # Name of the security group for Managed Service for OpenSearch cluster and Managed Service for Greenplum cluster 
  opensearch_port = 9200         # Managed Service for OpenSearch port for Internet connection  
  dashboards_port = 443          # Managed Service for OpenSearch port for connection to Dashboards

  # Settings for the Managed Service for OpenSearch cluster:
  mos_version     = "2.12"       # Version of the Managed Service for OpenSearch cluster   
  node_group_name = "mos-group"  # Node group name in the Managed Service for OpenSearch cluster
  dashboards_name = "dashboards" # Name of the dashboards node group in the Managed Service for OpenSearch cluster  

  # Settings for the Managed Service for Greenplum cluster:  
  mgp_version = "6.25" # Version of the Managed Service for Greenplum cluster     
}

resource "yandex_vpc_network" "mynet" {
  description = "Network for Managed Service for OpenSearch cluster and Managed Service for Greenplum cluster"
  name        = local.network_name
}

resource "yandex_vpc_subnet" "mysubnet" {
  description    = "Subnet for for Managed Service for OpenSearch cluster and Managed Service for Greenplum cluster"
  name           = local.subnet_name
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.mynet.id
  v4_cidr_blocks = ["10.1.0.0/16"]
}

resource "yandex_vpc_security_group" "mos-mgp-sg" {
  description = "Security group for Managed Service for OpenSearch cluster and Managed Service for Greenplum cluster"
  name        = local.sg_name
  network_id  = yandex_vpc_network.mynet.id

  ingress {
    description    = "Allow connections to the Managed Service for OpenSearch cluster from the Internet"
    protocol       = "TCP"
    port           = local.opensearch_port
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "Allow connections to the Managed Service for OpenSearch cluster Dashboards from the Internet"
    protocol       = "TCP"
    port           = local.dashboards_port
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "Allow connections to the Managed Service for Greenplum"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }

  egress {
    description    = "The rule allows all outgoing traffic"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

resource "yandex_mdb_opensearch_cluster" "my-os-cluster" {
  description        = "Managed Service for OpenSearch cluster"
  name               = local.mos_cluster_name
  environment        = "PRODUCTION"
  network_id         = yandex_vpc_network.mynet.id
  security_group_ids = [yandex_vpc_security_group.mos-mgp-sg.id]

  config {

    version        = local.mos_version
    admin_password = local.source_admin_password

    opensearch {
      node_groups {
        name             = local.node_group_name
        assign_public_ip = true
        hosts_count      = 1
        zone_ids         = ["ru-central1-a"]
        subnet_ids       = [yandex_vpc_subnet.mysubnet.id]
        roles            = ["DATA", "MANAGER"]
        resources {
          resource_preset_id = "s2.micro"  # 2 vCPU, 8 GB RAM
          disk_size          = 10737418240 # Bytes
          disk_type_id       = "network-ssd"
        }
      }
    }

    dashboards {
      node_groups {
        name             = local.dashboards_name
        assign_public_ip = true
        hosts_count      = 1
        zone_ids         = ["ru-central1-a"]
        subnet_ids       = [yandex_vpc_subnet.mysubnet.id]
        resources {
          resource_preset_id = "s2.micro"  # 2 vCPU, 8 GB RAM
          disk_size          = 10737418240 # Bytes
          disk_type_id       = "network-ssd"
        }
      }
    }
  }

  maintenance_window {
    type = "ANYTIME"
  }
}

resource "yandex_mdb_greenplum_cluster" "gp_cluster" {
  name               = local.mgp_cluster_name
  environment        = "PRODUCTION"
  network_id         = yandex_vpc_network.mynet.id
  zone               = "ru-central1-a"
  subnet_id          = yandex_vpc_subnet.mysubnet.id
  assign_public_ip   = true
  version            = local.mgp_version
  master_host_count  = 2
  segment_host_count = 2
  segment_in_host    = 2

  access {
    data_transfer = true
  }

  master_subcluster {
    resources {
      resource_preset_id = "s3-c8-m32" # 8 vCPU, 32 GB RAM
      disk_size          = 10          # GB
      disk_type_id       = "network-hdd"
    }
  }

  segment_subcluster {
    resources {
      resource_preset_id = "s3-c8-m32" # 8 vCPU, 32 GB RAM
      disk_size          = 93          # GB
      disk_type_id       = "network-ssd-nonreplicated"
    }
  }

  user_name     = local.mgp_username
  user_password = local.mgp_user_password

  security_group_ids = [yandex_vpc_security_group.mos-mgp-sg.id]
}

resource "yandex_datatransfer_transfer" "mos-to-mgp-transfer" {
  description = "Transfer from the Managed Service for OpenSearch cluster to the Managed Service for Greenplum cluster"
  count       = local.transfer_enabled
  name        = local.transfer_name
  source_id   = local.source_endpoint_id
  target_id   = local.target_endpoint_id
  type        = "SNAPSHOT_ONLY" # Copy all data from the source server

  provisioner "local-exec" {
    command = "yc --profile ${local.profile_name} datatransfer transfer activate ${yandex_datatransfer_transfer.mos-to-mgp-transfer[count.index].id}"
  }
}

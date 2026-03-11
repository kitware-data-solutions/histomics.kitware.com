resource "aws_security_group" "histomics_worker_sg" {
  name = "histomics-worker-sg"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "worker_ec2_ssh_key" {
  public_key = var.ssh_public_key
}

resource "aws_instance" "worker" {
  ami                    = var.worker_ami_id
  instance_type          = "t3.xlarge"
  count                  = 1
  vpc_security_group_ids = [aws_security_group.histomics_worker_sg.id]
  user_data              = <<EOF
#!/bin/bash
echo 'GIRDER_MONGO_URI=${local.mongodb_connection_string}' >> /etc/girder_worker.env
EOF
  key_name               = aws_key_pair.worker_ec2_ssh_key.key_name

  root_block_device {
    volume_size = 256
  }
}

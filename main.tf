resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true

  tags = {
    Name = "main-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "eu-west-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-sub"
  }
}

resource "aws_subnet" "private" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "eu-west-1a"


  tags = {
    Name = "private-sub"
  }
}

resource "aws_route_table" "public_to_igw" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table_association" "for_public" {
  route_table_id = aws_route_table.public_to_igw.id
  subnet_id = aws_subnet.public.id
}

resource "aws_route_table" "private_rt_to_nat_instance" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    instance_id = ""
  }
  tags = {
    Name = "privatr-rt"
  }
}

resource "aws_route_table_association" "private" {
  route_table_id = aws_route_table.private_rt_to_nat_instance
  subnet_id = aws_subnet.private.id
}

resource "aws_security_group" "nat_sg" {
   name        = "nat-sg"
  description = "Allow inbound HTTP and SSH"
  vpc_id      = aws_vpc.main.id

    ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nat-sg"
  }
}

resource "aws_security_group" "private_sg" {
  name        = "private-sg"
  description = "Allow HTTP traffic forwarded from NAT instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    # Allow traffic coming from the NAT instance security group.
    security_groups = [aws_security_group.nat_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "private-sg"
  }
}

data "aws_ami" "nat" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-vpc-nat-*"]
  }
}

resource "aws_instance" "nat" {
  ami                         = data.aws_ami.nat.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.nat_sg.id]
  key_name                    = "your-key-name"  # Replace with your key pair name

  # Disable source/destination checking so that the instance can function as a NAT.
  source_dest_check = false

  user_data = <<-EOF
    #!/bin/bash
    # Enable IP forwarding
    sysctl -w net.ipv4.ip_forward=1
    # Masquerade outbound traffic on eth0
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    # Forward incoming HTTP (port 80) traffic to the private instance (fixed private IP 10.0.2.10)
    iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination 10.0.2.10:80
    # Allow forwarded traffic (adjust rules as needed)
    iptables -A FORWARD -p tcp -d 10.0.2.10 --dport 80 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
  EOF

  tags = {
    Name = "nat-instance"
  }
}

resource "aws_eip" "nat_eip" {
  instance  = aws_instance.nat.id
  domain = "vpc"
  depends_on = [aws_internet_gateway.igw]
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "private" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private.id
  # Assign a fixed private IP so that the NAT instance can forward HTTP to it.
  private_ip             = "10.0.2.10"
  vpc_security_group_ids = [aws_security_group.private_sg.id]
  key_name               = "your-key-name"  # Replace with your key pair name

  user_data = <<-EOF
    #!/bin/bash
    # Update and install Docker
    yum update -y
    amazon-linux-extras install docker -y
    service docker start
    # Prepare a directory for custom content
    mkdir -p /home/ec2-user/html
    echo "Yo this is nginx" > /home/ec2-user/html/index.html
    # Run an Nginx container with the custom index page mounted
    docker run -d -p 80:80 -v /home/ec2-user/html:/usr/share/nginx/html nginx
  EOF

  tags = {
    Name = "private-nginx"
  }
}

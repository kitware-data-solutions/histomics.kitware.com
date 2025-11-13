output "dns_name_servers" {
  description = "Name servers for the DNS zone"
  value       = aws_route53_zone.primary.name_servers
}


output "sg_alb_id" {
  value = aws_security_group.sg_alb.id
}

output "sg_app_id" {
  value = aws_security_group.sg_app.id
}

output "sg_db_id" {
  value = aws_security_group.sg_db.id
}
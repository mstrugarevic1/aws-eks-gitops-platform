output "dashboard_name" {
  value = aws_cloudwatch_dashboard.service.dashboard_name
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

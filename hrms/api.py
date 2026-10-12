"""
Health check API endpoint for Openship container orchestration.
Used by container health checks and orchestration systems to verify app status.
"""

import frappe
from frappe import response


@frappe.whitelist(allow_guest=True, methods=["GET"])
def health_check():
	"""
	Health check endpoint for container orchestration.
	Returns 200 OK if Frappe is running and database is accessible.
	"""
	try:
		# Check database connectivity
		frappe.db.sql("SELECT 1")
		
		return {
			"status": "healthy",
			"message": "Frappe HRMS is running",
		}
	except Exception as e:
		# Log the error but return 503 Service Unavailable
		frappe.log_error(title="Health Check Failed", message=str(e))
		response.status_code = 503
		return {
			"status": "unhealthy",
			"message": f"Database check failed: {str(e)}",
		}

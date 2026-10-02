package core

// AdminUsername preserves the historical default when updating older installs.
func AdminUsername() string {
	name, _ := GetValue("admin_user")
	if name == "" {
		return "admin"
	}
	return name
}

# Disaster recovery

Application backup and HSM key backup are separate concerns. Restore PostgreSQL/config first, then provision the secondary HSM with the correct DKEK shares/wrapped key through an audited ceremony, verify a test signature, and only then activate signing.

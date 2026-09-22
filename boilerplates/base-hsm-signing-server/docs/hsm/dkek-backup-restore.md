# DKEK backup and restore design

SmartCard-HSM backup/restore requires the device to be initialized with a DKEK/key domain before exportable production keys are generated. The implementation must guide an m-of-n ceremony, show key-check values, process share material only in memory, wrap selected keys, and verify restoration onto the secondary HSM.

Operational rule: never label a DR backup successful merely because a wrapped blob exists. A scheduled/manual recovery test must import onto the designated DR token and verify the public key/certificate fingerprint and a test signature.

use anyhow::Result;
#[tokio::main]
async fn main()->Result<()> {
  tracing_subscriber::fmt().json().init();
  tracing::info!(service="signzone-signerd", "starting safe skeleton");
  // SECURITY-BLOCKED: implement Unix socket permissions, peer credentials, typed RPC,
  // OpenSC/PKCS#11 provider integration, HSM allowlists, policy token verification,
  // safe credential retrieval, audit correlation, timeout and post-sign verification.
  tokio::signal::ctrl_c().await?;
  Ok(())
}

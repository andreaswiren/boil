use serde::{Deserialize,Serialize};
#[derive(Debug,Serialize,Deserialize)]
pub struct RpcEnvelope<T>{pub request_id:String,pub body:T}
#[derive(Debug,Serialize,Deserialize)]
pub enum SignerRequest{Status,ListDevices,SignArtifact{request_id:String,profile:String,artifact_path:String,expected_sha256:String}}
#[derive(Debug,Serialize,Deserialize)]
pub enum OsRequest{Status,GetNetwork,GetFirewall,RestartApprovedService{service:String},BeginNetworkTransaction{candidate_id:String},ConfirmNetworkTransaction{candidate_id:String}}

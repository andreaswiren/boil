export async function GET(){return Response.json({setupMode:process.env.SIGNZONE_SETUP_MODE==="1"});}

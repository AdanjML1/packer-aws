const express = require("express");
const app = express();

app.get("/", (req, res) => {
  res.send("Hola desde mi AMI con Node.js y Packer");
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`Servidor iniciado en puerto ${port}`));

const express = require('express');
const path = require('path');
const app = express();
const PORT = process.env.PORT || 80;

// Middleware para servir archivos estáticos
app.use(express.static(__dirname));

// Redirección básica a login como entrada
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'login.html'));
});

// Iniciar el servidor
app.listen(PORT, () => {
     console.log(`Servidor corriendo en http://localhost:${PORT}`);
});
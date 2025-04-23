const productos = [
    { id: 1, nombre: "Spider-Man #1", precio: 5.99, imagen: "images/spiderman.jpg" },
    { id: 2, nombre: "Batman: Año Uno", precio: 7.49, imagen: "images/batman.jpg" },
    { id: 3, nombre: "X-Men: Días del Futuro Pasado", precio: 6.99, imagen: "images/xmen.jpg" }
  ];
  
  const carrito = {};
  
  const catalogo = document.getElementById("catalogo");
  const carritoItems = document.getElementById("carritoItems");
  const totalEl = document.getElementById("total");
  
  function renderCatalogo() {
    productos.forEach(p => {
      const div = document.createElement("div");
      div.className = "card";
      div.innerHTML = `
        <img src="${p.imagen}" alt="${p.nombre}">
        <h3>${p.nombre}</h3>
        <p>$${p.precio.toFixed(2)}</p>
        <button onclick="agregarCarrito(${p.id})">Añadir al carrito</button>
      `;
      catalogo.appendChild(div);
    });
  }
  
  function agregarCarrito(id) {
    carrito[id] = (carrito[id] || 0) + 1;
    actualizarCarrito();
  }
  
  function actualizarCarrito() {
    carritoItems.innerHTML = '';
    let total = 0;
    for (let id in carrito) {
      const p = productos.find(prod => prod.id == id);
      const cantidad = carrito[id];
      const subtotal = cantidad * p.precio;
      total += subtotal;
  
      const item = document.createElement("p");
      item.innerHTML = `${p.nombre} x ${cantidad} = $${subtotal.toFixed(2)}
        <button onclick="quitarCarrito(${id})" style="margin-left:10px;">X</button>`;
      carritoItems.appendChild(item);
    }
    totalEl.textContent = total.toFixed(2);
  }
  
  function quitarCarrito(id) {
    if (carrito[id] > 1) {
      carrito[id]--;
    } else {
      delete carrito[id];
    }
    actualizarCarrito();
  }
  
  function pagar() {
    if (Object.keys(carrito).length === 0) {
      alert("El carrito está vacío.");
      return;
    }
    alert("Pago exitoso. ¡Gracias por tu compra!");
    for (let id in carrito) delete carrito[id];
    actualizarCarrito();
  }
  
  renderCatalogo();
  
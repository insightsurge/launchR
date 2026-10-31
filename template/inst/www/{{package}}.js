const button = document.querySelector('#hello');
if (button) {
  button.addEventListener('click', () => {
    button.textContent = 'Hello!';
  });
}

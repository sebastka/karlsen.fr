document.addEventListener("DOMContentLoaded", async function(event) {
    var content = await fetch('karlsen.fr.ascii')
        .then((response) => response.text())
        .then((data) => {
            return data;
        }
    );

    document.getElementById('hostname-pre').innerHTML = content;
});

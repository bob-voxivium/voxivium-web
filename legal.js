document.addEventListener('DOMContentLoaded', () => {
    // Define the email parts separately
    const user = 'le' + 'gal';
    const domain = 'voxivi' + 'um.com';

    // Find the target element in the HTML
    const emailContainer = document.getElementById('legal-email-link');

    if (emailContainer) {
        // Combine the parts to form the full email address
        const fullEmail = `${user}@${domain}`;

        // Create a mailto link element
        const mailLink = document.createElement('a');
        mailLink.href = `mailto:${fullEmail}`;
        mailLink.textContent = fullEmail;

        // Add the complete link to the page
        emailContainer.appendChild(mailLink);
    }
});

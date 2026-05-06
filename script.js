/*
    script.js
    Contains all the interactive logic for the Voxivium website.
*/

document.addEventListener('DOMContentLoaded', function () {
    
    // --- Mobile Menu Logic ---
    // Handles the opening and closing of the slide-out menu on mobile devices.
    const menuButton = document.getElementById('menu-button');
    const closeMenuButton = document.getElementById('close-menu-button');
    const menu = document.getElementById('menu');

    if (menuButton && closeMenuButton && menu) {
        menuButton.addEventListener('click', () => {
            menu.classList.remove('menu-hidden');
        });

        closeMenuButton.addEventListener('click', () => {
            menu.classList.add('menu-hidden');
        });
    }

    // --- State Population for Forms ---
    // An array of US states to populate the dropdown menus in the forms.
    const states = [
        "Alabama", "Alaska", "Arizona", "Arkansas", "California", "Colorado", "Connecticut", "Delaware",
        "Florida", "Georgia", "Hawaii", "Idaho", "Illinois", "Indiana", "Iowa", "Kansas", "Kentucky",
        "Louisiana", "Maine", "Maryland", "Massachusetts", "Michigan", "Minnesota", "Mississippi",
        "Missouri", "Montana", "Nebraska", "Nevada", "New Hampshire", "New Jersey", "New Mexico",
        "New York", "North Carolina", "North Dakota", "Ohio", "Oklahoma", "Oregon", "Pennsylvania",
        "Rhode Island", "South Carolina", "South Dakota", "Tennessee", "Texas", "Utah", "Vermont",
        "Virginia", "Washington", "West Virginia", "Wisconsin", "Wyoming"
    ];

    // Populates all select elements with the name 'state'.
    const stateSelects = document.querySelectorAll('select[name="state"]');
    stateSelects.forEach(select => {
        states.forEach(state => {
            const option = document.createElement('option');
            option.value = state;
            option.textContent = state;
            select.appendChild(option);
        });
    });

    // --- Form Handling Logic ---
    // Manages validation and submission for both sign-up forms.
    const forms = [document.getElementById('signup-form-top'), document.getElementById('signup-form-bottom')];
    
    forms.forEach(form => {
        if(form) {
            form.addEventListener('submit', function (event) {
                event.preventDefault();
                if (validateForm(form)) {
                    submitForm(form);
                }
            });
        }
    });

    /**
     * Validates the form fields (firstName, email, state).
     * @param {HTMLFormElement} form - The form element to validate.
     * @returns {boolean} - True if the form is valid, false otherwise.
     */
    function validateForm(form) {
        let isValid = true;
        const inputs = form.querySelectorAll('input[required], select[required]');
        
        inputs.forEach(input => {
            const validationMessageElement = form.querySelector(`[data-validation-for="${input.name}"]`);
            validationMessageElement.classList.add('hidden');
            input.classList.remove('border-red-500');

            let message = '';
            if (!input.value.trim()) {
                message = 'This field is required.';
            } else if (input.name === 'email' && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(input.value)) {
                message = 'Please enter a valid email address.';
            } else if (input.name === 'firstName' && input.value.lenght > 24 && !/^[a-zA-Z\s'-]+$/.test(input.value)) {
                message = 'Please enter a valid name less than 25 characters with only letters, spaces, apostrophes and hyphens.';
            }

            if (message) {
                isValid = false;
                validationMessageElement.textContent = message;
                validationMessageElement.classList.remove('hidden');
                input.classList.add('border-red-500');
            }
        });

        return isValid;
    }

    /**
     * Handles the form submission process, including API call and UI updates.
     * @param {HTMLFormElement} form - The form element being submitted.
     */
    async function submitForm(form) {
        const formData = new FormData(form);
        const data = {
            firstName: formData.get('firstName'),
            email: formData.get('email'),
            state: formData.get('state')
        };

        // IMPORTANT: Replace this placeholder with your actual AWS API Gateway URL.
        const apiUrl = 'https://3o61p10ex0.execute-api.us-east-1.amazonaws.com/prod/signup';
        
        const button = form.querySelector('button[type="submit"]');
        button.disabled = true;
        button.innerHTML = '<span class="animate-pulse">Submitting...</span>';

        const formContainer = form.parentElement.parentElement;

        try {
            const response = await fetch(apiUrl, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(data),
            });

            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }

            // Display a success message to the user.
            formContainer.innerHTML = `
                <div class="text-center p-8">
                    <div class="flex items-center justify-center h-16 w-16 rounded-full bg-green-100 text-green-600 mx-auto">
                       <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path></svg>
                    </div>
                    <h2 class="text-2xl font-semibold text-center text-gray-800 mt-6">Thank You!</h2>
                    <p class="text-center text-gray-600 mt-2">You're on the list! We'll notify you as soon as the Voxivium app is ready to launch.</p>
                </div>
            `;

        } catch (error) {
            console.error('Submission failed:', error);
            // Display an error message to the user.
             formContainer.innerHTML = `
                <div class="text-center p-8">
                     <div class="flex items-center justify-center h-16 w-16 rounded-full bg-red-100 text-red-600 mx-auto">
                       <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>
                    </div>
                    <h2 class="text-2xl font-semibold text-center text-gray-800 mt-6">Submission Failed</h2>
                    <p class="text-center text-gray-600 mt-2">Something went wrong. Please try again later.</p>
                </div>
            `;
        }
    }
});

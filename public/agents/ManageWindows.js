/**
 * @description Sends system management data to the PsWebHost server.
 * @param {object} data The data to send. Should match the expected JSON structure.
 * @param {string} data.ComputerName The name of the computer.
 * @param {string} data.Public_IP The public IP of the computer.
 * @param {Array} data.Disks An array of disk information.
 * @returns {Promise<object>} A promise that resolves to the JSON response from the server.
 */
async function sendManagementData(data) {
    const endpoint = '/api/ManageWindows';

    try {
        const response = await fetch(endpoint, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                // In a real application, this token would be acquired through an auth flow.
                'Authorization': 'Bearer-Valid-Token' 
            },
            body: JSON.stringify(data)
        });

        return await response.json();

    } catch (error) {
        console.error('Error sending management data:', error);
        return { Status: 'Error', Message: 'Client-side error.', Details: error };
    }
}

/**
 * Example usage of the sendManagementData function.
 */
function runExample() {
    const exampleData = {
        ComputerName: 'CLIENT-PC-01',
        Public_IP: '198.51.100.1',
        Disks: [
            { Name: 'C:', SizeGB: 500, FreeGB: 250 },
            { Name: 'D:', SizeGB: 1000, FreeGB: 500 }
        ]
    };

    console.log('Sending example management data...', exampleData);

    sendManagementData(exampleData)
        .then(response => {
            console.log('Server response:', response);
        });
}

// To run the example, open the browser's developer console and type:
// runExample();

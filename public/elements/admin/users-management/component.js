const { useState, useEffect } = React;

const UserManagement = () => {
    const [users, setUsers] = useState([]);
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [currentUser, setCurrentUser] = useState(null);

    useEffect(() => {
        fetchUsers();
    }, []);

    const fetchUsers = () => {
        fetch("/api/v1/users")
            .then(response => response.json())
            .then(data => setUsers(data));
    };

    const handleOpenModal = (user) => {
        setCurrentUser(user);
        setIsModalOpen(true);
    };

    const handleCloseModal = () => {
        setCurrentUser(null);
        setIsModalOpen(false);
    };

    const handleDeleteUser = (userId) => {
        fetch(`/api/v1/users?UserID=${userId}`, { method: 'DELETE' })
            .then(() => fetchUsers());
    };

    const handleSaveUser = (userData, file) => {
        const formData = new FormData();
        formData.append("UserName", userData.UserName);
        formData.append("Email", userData.Email);
        formData.append("Phone", userData.Phone);
        if (file) {
            formData.append("profileImage", file);
        }

        const url = userData.UserID ? `/api/v1/users?UserID=${userData.UserID}` : '/api/v1/users';
        const method = userData.UserID ? 'POST' : 'PUT';

        fetch(url, { method: method, body: formData })
            .then(() => {
                fetchUsers();
                handleCloseModal();
            });
    };

    return (
        <div>
            <h1>User Management</h1>
            <button onClick={() => handleOpenModal(null)}>Create User</button>
            <table>
                <thead>
                    <tr>
                        <th>Username</th>
                        <th>Email</th>
                        <th>Phone</th>
                        <th>Actions</th>
                    </tr>
                </thead>
                <tbody>
                    {users.map(user => (
                        <tr key={user.UserID}>
                            <td>{user.UserName}</td>
                            <td>{user.Email}</td>
                            <td>{user.Phone}</td>
                            <td>
                                <button onClick={() => handleOpenModal(user)}>Edit</button>
                                <button onClick={() => handleDeleteUser(user.UserID)}>Delete</button>
                            </td>
                        </tr>
                    ))}
                </tbody>
            </table>

            {isModalOpen && (
                <UserModal 
                    user={currentUser} 
                    onClose={handleCloseModal} 
                    onSave={handleSaveUser} 
                />
            )}
        </div>
    );
};

const UserModal = ({ user, onClose, onSave }) => {
    const [userData, setUserData] = useState(user || {});
    const [profileImage, setProfileImage] = useState(null);

    const handleChange = (e) => {
        const { name, value } = e.target;
        setUserData(prev => ({ ...prev, [name]: value }));
    };

    const handleFileChange = (e) => {
        setProfileImage(e.target.files[0]);
    };

    const handleSave = () => {
        onSave(userData, profileImage);
    };

    return (
        <div className="modal">
            <div className="modal-content">
                <h2>{user ? 'Edit User' : 'Create User'}</h2>
                <label>Username:</label>
                <input type="text" name="UserName" value={userData.UserName || ''} onChange={handleChange} />
                <label>Email:</label>
                <input type="email" name="Email" value={userData.Email || ''} onChange={handleChange} />
                <label>Phone:</label>
                <input type="text" name="Phone" value={userData.Phone || ''} onChange={handleChange} />
                <label>Profile Picture:</label>
                <input type="file" onChange={handleFileChange} />
                <button onClick={handleSave}>Save</button>
                <button onClick={onClose}>Cancel</button>
            </div>
        </div>
    );
};

ReactDOM.render(<UserManagement />, document.getElementById('user-management-root'));

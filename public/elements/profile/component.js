const ProfileComponent = () => {
    const { useState, useEffect } = React;
    const [profile, setProfile] = useState({ fullName: '', email: '', phone: '', bio: '' });
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    const [message, setMessage] = useState('');

    useEffect(() => {
        window.psweb_fetchWithAuthHandling('/api/v1/config/profile')
            .then(response => response.json())
            .then(data => {
                setProfile(data);
                setLoading(false);
            })
            .catch(err => {
                setError('Failed to load profile data.');
                setLoading(false);
            });
    }, []);

    const handleChange = (e) => {
        setProfile({ ...profile, [e.target.name]: e.target.value });
    };

    const handleSubmit = (e) => {
        e.preventDefault();
        setMessage('');
        setError(null);

        window.psweb_fetchWithAuthHandling('/api/v1/config/profile', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(profile),
        })
        .then(response => response.json())
        .then(data => {
            if (data.status === 'success') {
                setMessage(data.message);
            } else {
                setError(data.message || 'An error occurred while saving.');
            }
        })
        .catch(err => {
            setError('An unexpected error occurred.');
        });
    };

    if (loading) return <div>Loading profile...</div>;

    return (
        <div style={{ padding: '20px' }}>
            <h3>User Profile</h3>
            <form onSubmit={handleSubmit}>
                <div style={{ marginBottom: '10px' }}>
                    <label>Full Name</label><br/>
                    <input type="text" name="fullName" value={profile.fullName} onChange={handleChange} style={{ width: '100%' }} />
                </div>
                <div style={{ marginBottom: '10px' }}>
                    <label>Email</label><br/>
                    <input type="email" name="email" value={profile.email} onChange={handleChange} style={{ width: '100%' }} readOnly />
                </div>
                <div style={{ marginBottom: '10px' }}>
                    <label>Phone</label><br/>
                    <input type="text" name="phone" value={profile.phone} onChange={handleChange} style={{ width: '100%' }} />
                </div>
                <div style={{ marginBottom: '10px' }}>
                    <label>Bio</label><br/>
                    <textarea name="bio" value={profile.bio} onChange={handleChange} style={{ width: '100%', height: '100px' }} />
                </div>
                <button type="submit">Save Profile</button>
            </form>
            {message && <div style={{ color: 'green', marginTop: '10px' }}>{message}</div>}
            {error && <div style={{ color: 'red', marginTop: '10px' }}>{error}</div>}
        </div>
    );
};

window.cardComponents['profile'] = ProfileComponent;
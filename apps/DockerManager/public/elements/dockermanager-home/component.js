// Docker Manager Home Component
class DockerManagerHome extends React.Component {
    constructor(props) {
        super(props);
        this.state = {
            status: null,
            loading: true,
            error: null
        };
    }

    async componentDidMount() {
        await this.loadStatus();
    }

    async loadStatus() {
        try {
            const response = await window.psweb_fetchWithAuthHandling('/apps/dockermanager/api/v1/status');
            if (!response.ok) throw new Error(HTTP ${response.status}: ${response.statusText});
            const data = await response.json();
            this.setState({ status: data, loading: false });
        } catch (error) {
            this.setState({ error: error.message, loading: false });
        }
    }

    render() {
        const { status, loading, error } = this.state;

        if (loading) {
            return React.createElement('div', { className: 'dockermanager-home' },
                React.createElement('p', null, 'Loading...')
            );
        }

        if (error) {
            return React.createElement('div', { className: 'dockermanager-home' },
                React.createElement('div', { className: 'error' },
                    React.createElement('strong', null, 'Error: '),
                    error
                )
            );
        }

        return React.createElement('div', { className: 'dockermanager-home' },
            React.createElement('h2', null, 'Docker Manager'),
            React.createElement('div', { className: 'status-card' },
                React.createElement('p', null, Category: ${status.category}),
                React.createElement('p', null, `SubCategory: ``),

                React.createElement('p', null, Status: ${status.status}),
                React.createElement('p', null, Version: ${status.version})
            )
        );
    }
}

// Register with card loader
window.customElements.define('dockermanager-home', class extends HTMLElement {
    connectedCallback() {
        ReactDOM.render(
            React.createElement(DockerManagerHome),
            this
        );
    }
});

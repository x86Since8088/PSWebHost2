// Task Scheduler Component
// Design Intentions:
// - Platform-aware: Windows Task Scheduler / Linux Cron
// - Display scheduled tasks with next run times
// - Allow creating, editing, and deleting tasks
// - Show task history and run results
// - Enable/disable tasks
// - View task logs

const TaskSchedulerComponent = ({ url, element }) => {
    const [tasks, setTasks] = React.useState([]);
    const [loading, setLoading] = React.useState(true);
    const [platform, setPlatform] = React.useState('windows');

    React.useEffect(() => {
        // Fetch scheduled tasks from backend API
        fetch('/apps/windowsadmin/api/v1/system/tasks')
            .then(response => {
                if (!response.ok) throw new Error(`HTTP ${response.status}: ${response.statusText}`);
                return response.json();
            })
            .then(data => {
                setPlatform(data.platform.toLowerCase());
                // Map backend data to component format
                const mappedTasks = data.tasks.map(task => ({
                    name: task.name,
                    path: task.path,
                    schedule: task.schedule || 'N/A',
                    lastRun: task.lastRun || 'Never',
                    nextRun: task.nextRun || 'N/A',
                    status: task.enabled ? 'enabled' : 'disabled',
                    state: task.state,
                    result: task.lastResult === 0 ? 'success' : (task.lastResult ? 'failed' : 'unknown')
                }));
                setTasks(mappedTasks);
                setLoading(false);
            })
            .catch(error => {
                console.error('Failed to load scheduled tasks:', error);
                setLoading(false);
                // Keep empty tasks array on error
            });
    }, []);

    const getResultColor = (result) => {
        switch (result) {
            case 'success': return '#4caf50';
            case 'failed': return '#f44336';
            case 'skipped': return '#ff9800';
            default: return '#9e9e9e';
        }
    };

    if (loading) {
        return React.createElement('div', { className: 'task-scheduler loading' },
            React.createElement('p', null, 'Loading scheduled tasks...')
        );
    }

    return React.createElement('div', {
        className: 'task-scheduler',
        style: { padding: '16px', height: '100%', overflow: 'auto' }
    },
        // Design note
        React.createElement('div', { className: 'design-note', style: {
            background: 'var(--bg-secondary)',
            padding: '16px',
            borderRadius: '8px',
            marginBottom: '16px',
            border: '2px dashed var(--accent-color)'
        }},
            React.createElement('h3', { style: { margin: '0 0 8px 0' } }, '🚧 Implementation Pending'),
            React.createElement('p', { style: { margin: 0 } },
                'This component will manage scheduled tasks. ',
                platform === 'windows'
                    ? 'Integrates with Windows Task Scheduler.'
                    : 'Manages cron jobs and systemd timers.'
            )
        ),

        // Header
        React.createElement('div', { style: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' } },
            React.createElement('h2', { style: { margin: 0 } },
                platform === 'windows' ? '📅 Windows Task Scheduler' : '⏰ Cron Jobs'
            ),
            React.createElement('button', {
                disabled: true,
                style: { padding: '8px 16px', cursor: 'not-allowed', opacity: 0.5 }
            }, '+ New Task')
        ),

        // Tasks table
        React.createElement('table', { style: { width: '100%', borderCollapse: 'collapse' } },
            React.createElement('thead', null,
                React.createElement('tr', { style: { borderBottom: '2px solid var(--border-color)' } },
                    React.createElement('th', { style: { textAlign: 'left', padding: '10px' } }, 'Task'),
                    React.createElement('th', { style: { textAlign: 'left', padding: '10px' } }, 'Schedule'),
                    React.createElement('th', { style: { textAlign: 'left', padding: '10px' } }, 'Last Run'),
                    React.createElement('th', { style: { textAlign: 'left', padding: '10px' } }, 'Next Run'),
                    React.createElement('th', { style: { textAlign: 'center', padding: '10px' } }, 'Status'),
                    React.createElement('th', { style: { textAlign: 'center', padding: '10px' } }, 'Result'),
                    React.createElement('th', { style: { textAlign: 'center', padding: '10px' } }, 'Actions')
                )
            ),
            React.createElement('tbody', null,
                tasks.map(task =>
                    React.createElement('tr', {
                        key: task.name,
                        style: {
                            borderBottom: '1px solid var(--border-color)',
                            opacity: task.status === 'disabled' ? 0.5 : 1
                        }
                    },
                        React.createElement('td', { style: { padding: '10px', fontWeight: 'bold' } }, task.name),
                        React.createElement('td', { style: { padding: '10px', fontFamily: 'monospace' } }, task.schedule),
                        React.createElement('td', { style: { padding: '10px', fontSize: '0.9em' } }, task.lastRun),
                        React.createElement('td', { style: { padding: '10px', fontSize: '0.9em' } }, task.nextRun),
                        React.createElement('td', { style: { textAlign: 'center', padding: '10px' } },
                            React.createElement('span', { style: {
                                padding: '2px 8px',
                                borderRadius: '10px',
                                fontSize: '0.85em',
                                background: task.status === 'enabled' ? 'rgba(76, 175, 80, 0.2)' : 'rgba(158, 158, 158, 0.2)'
                            }}, task.status)
                        ),
                        React.createElement('td', { style: { textAlign: 'center', padding: '10px' } },
                            React.createElement('span', { style: {
                                color: getResultColor(task.result)
                            }}, task.result)
                        ),
                        React.createElement('td', { style: { textAlign: 'center', padding: '10px' } },
                            React.createElement('button', {
                                disabled: true,
                                title: 'Run Now',
                                style: { marginRight: '4px', padding: '4px 8px', cursor: 'not-allowed', opacity: 0.5 }
                            }, '▶️'),
                            React.createElement('button', {
                                disabled: true,
                                title: 'Edit',
                                style: { marginRight: '4px', padding: '4px 8px', cursor: 'not-allowed', opacity: 0.5 }
                            }, '✏️'),
                            React.createElement('button', {
                                disabled: true,
                                title: 'View Logs',
                                style: { padding: '4px 8px', cursor: 'not-allowed', opacity: 0.5 }
                            }, '📋')
                        )
                    )
                )
            )
        )
    );
};

window.cardComponents = window.cardComponents || {};
window.cardComponents['task-scheduler'] = TaskSchedulerComponent;

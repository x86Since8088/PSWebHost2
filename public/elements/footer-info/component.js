const { useState, useEffect } = React;

const FooterInfoCard = ({ element }) => {
    return (
        <div>{element.Content}</div>
    );
};

window.cardComponents['footer-info'] = FooterInfoCard;

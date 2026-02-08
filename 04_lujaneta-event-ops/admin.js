// ================= CONFIGURACIÓN =================
const SUPABASE_URL = 'https://xsutpmbhvzuvjpwwyoli.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzdXRwbWJodnp1dmpwd3d5b2xpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAzNzUwNTMsImV4cCI6MjA4NTk1MTA1M30.ym7wCHRwpit-4OaHM9V3JSzbR-baH1WfEYIAFfbAgBo';
const supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

let CURRENT_USER_ROLE = null;
let ALL_DATA = []; 

document.addEventListener('DOMContentLoaded', async () => {
    await checkAuthAndRole();
    fetchRegistrations();
});

// --- SEGURIDAD ---
async function checkAuthAndRole() {
    const { data: { session } } = await supabaseClient.auth.getSession();
    if (!session) { window.location.href = 'login.html'; return; }
    
    document.getElementById('userEmail').textContent = session.user.email;

    const { data: roleData } = await supabaseClient
        .from('user_roles')
        .select('role')
        .eq('user_id', session.user.id)
        .single();

    if (roleData) {
        CURRENT_USER_ROLE = roleData.role;
        document.getElementById('userEmail').innerHTML += ` <span style="background:#eef2f7; padding:2px 6px; border-radius:4px; font-size:0.8em; border:1px solid #ccc;">${CURRENT_USER_ROLE}</span>`;
    } else {
        logout();
    }
}

window.logout = async () => {
    await supabaseClient.auth.signOut();
    localStorage.clear();
    window.location.href = 'login.html';
};

// --- CARGAR DATOS ---
async function fetchRegistrations() {
    const tableBody = document.getElementById('tableBody');
    const table = document.getElementById('registrationsTable');
    const loading = document.getElementById('loading');
    
    loading.style.display = 'block';
    table.style.display = 'none';
    tableBody.innerHTML = '';

    // CORRECCIÓN: Usamos 'fitness' (nombre real) y 'medical_notes'
    const { data, error } = await supabaseClient
        .from('registrations')
        .select(`
            registration_id, created_at, payment_status, fitness,
            participants ( full_name, doc_number, phone, emergency_contact_name, emergency_contact_phone, medical_notes ),
            payments ( amount, method, proof_file_url, status )
        `)
        .order('created_at', { ascending: false });

    if (error) { 
        console.error(error);
        alert("Error cargando datos: " + error.message); 
        return; 
    }

    ALL_DATA = data; 
    renderTable(data); 
    updateKPIs(data);

    loading.style.display = 'none';
    table.style.display = 'table';
}

function renderTable(data) {
    const tableBody = document.getElementById('tableBody');
    tableBody.innerHTML = '';

    if (!data || data.length === 0) {
        tableBody.innerHTML = '<tr><td colspan="6" style="text-align:center;">No se encontraron datos.</td></tr>';
        return;
    }

    data.forEach(reg => {
        const p = reg.participants;
        const pay = reg.payments && reg.payments.length > 0 ? reg.payments[0] : null;
        
        const row = document.createElement('tr');
        const date = new Date(reg.created_at).toLocaleDateString('es-AR', {day:'2-digit', month:'2-digit'});
        
        let badgeClass = reg.payment_status === 'Verified' ? 'badge-verified' : (reg.payment_status === 'Rejected' ? 'badge-rejected' : 'badge-submitted');
        
        // Icono de Alerta Médica
        let healthIcon = '<span style="color:#ccc">OK</span>';
        if (p.medical_notes && p.medical_notes.length > 2 && p.medical_notes !== 'Ninguna') {
            healthIcon = '<span style="color:#c0392b; font-weight:bold; font-size:1.2em;" title="Ver Ficha Médica">⚠️ Alerta</span>';
        }

        // Botones según Rol
        let actionsHtml = `<button class="btn-action btn-view" onclick='openModal(${JSON.stringify(reg)})' title="Ver Ficha">👁️</button>`;

        const isPending = (reg.payment_status === 'Submitted' || reg.payment_status === 'Pending');
        const canEdit = (CURRENT_USER_ROLE === 'Admin' || CURRENT_USER_ROLE === 'Ops');

        if (isPending && canEdit) {
            actionsHtml += `
                <button class="btn-action btn-approve" onclick="approveRegistration('${reg.registration_id}')">✓</button>
                <button class="btn-action btn-reject" onclick="rejectRegistration('${reg.registration_id}')">✗</button>
            `;
        }

        row.innerHTML = `
            <td>
                <strong>${p ? p.full_name : 'Desconocido'}</strong><br>
                <small style="color:#666">📅 ${date}</small>
            </td>
            <td>${p ? p.doc_number : '-'}</td>
            <td>$${pay ? pay.amount : '0'}</td>
            <td style="text-align:center;">${healthIcon}</td>
            <td><span class="badge ${badgeClass}">${reg.payment_status}</span></td>
            <td>${actionsHtml}</td>
        `;
        tableBody.appendChild(row);
    });
}

// --- BUSCADOR ---
window.filterTable = () => {
    const searchText = document.getElementById('searchInput').value.toLowerCase();
    const filtered = ALL_DATA.filter(item => {
        const name = item.participants?.full_name?.toLowerCase() || '';
        const dni = item.participants?.doc_number?.toString() || '';
        return name.includes(searchText) || dni.includes(searchText);
    });
    renderTable(filtered);
};

// --- MODAL ---
window.openModal = (reg) => {
    const p = reg.participants;
    
    document.getElementById('m-name').textContent = p.full_name;
    
    const emergenciaTexto = (p.emergency_contact_name || '') + ' ' + (p.emergency_contact_phone ? `(${p.emergency_contact_phone})` : '');
    document.getElementById('m-emergency').textContent = emergenciaTexto.trim() || "No especificado";
    
    let medicalText = "Sin observaciones.";
    if (p.medical_notes) {
        medicalText = `<strong>Condiciones/Alergias:</strong><br> ${p.medical_notes}`;
    }
    document.getElementById('m-medical').innerHTML = medicalText;
    
    document.getElementById('m-fitness').textContent = reg.fitness || "-"; // Nombre correcto
    
    document.getElementById('detailsModal').style.display = 'flex';
};

window.closeModal = () => {
    document.getElementById('detailsModal').style.display = 'none';
};

// --- KPIs ---
function updateKPIs(data) {
    if (!data) return;
    document.getElementById('kpi-total').textContent = data.length;
    const verifiedTotal = data.filter(r => r.payment_status === 'Verified').reduce((sum, r) => sum + (r.payments?.[0]?.amount || 0), 0);
    document.getElementById('kpi-money').textContent = `$${verifiedTotal.toLocaleString('es-AR')}`;
    document.getElementById('kpi-pending').textContent = data.filter(r => r.payment_status === 'Submitted').length;
}

// --- ACCIONES APROBAR/RECHAZAR ---
window.approveRegistration = async (regId) => {
    if (CURRENT_USER_ROLE === 'Staff') return;
    if (!confirm("¿Aprobar pago?")) return;
    await supabaseClient.from('registrations').update({ payment_status: 'Verified', registration_status: 'Registered' }).eq('registration_id', regId);
    await supabaseClient.from('payments').update({ status: 'Verified' }).eq('registration_id', regId);
    fetchRegistrations();
};

window.rejectRegistration = async (regId) => {
    if (CURRENT_USER_ROLE === 'Staff') return;
    const reason = prompt("Motivo:");
    if (!reason) return;
    await supabaseClient.from('registrations').update({ payment_status: 'Rejected' }).eq('registration_id', regId);
    await supabaseClient.from('payments').update({ status: 'Rejected', rejection_reason: reason }).eq('registration_id', regId);
    fetchRegistrations();
};

// --- NUEVO: EXPORTAR A EXCEL ---
window.exportToCSV = () => {
    if (!ALL_DATA || ALL_DATA.length === 0) {
        alert("No hay datos para exportar.");
        return;
    }

    let csvContent = "data:text/csv;charset=utf-8,";
    csvContent += "FECHA,NOMBRE,DNI,TELEFONO,EMERGENCIA,PAGO_ESTADO,MONTO,FITNESS,NOTAS_MEDICAS\n";

    ALL_DATA.forEach(reg => {
        const p = reg.participants;
        const pay = reg.payments && reg.payments.length > 0 ? reg.payments[0] : null;
        const date = new Date(reg.created_at).toLocaleDateString('es-AR');
        
        // Limpiamos comas para que no rompa el CSV
        const cleanName = (p.full_name || "").replace(/,/g, "");
        const cleanNotes = (p.medical_notes || "").replace(/,/g, " ").replace(/\n/g, " ");
        const cleanEmergency = (p.emergency_contact_name || "") + " " + (p.emergency_contact_phone || "");

        const row = [
            date,
            cleanName,
            p.doc_number,
            p.phone,
            cleanEmergency,
            reg.payment_status,
            pay ? pay.amount : 0,
            reg.fitness || "-",
            cleanNotes
        ].join(",");

        csvContent += row + "\n";
    });

    const encodedUri = encodeURI(csvContent);
    const link = document.createElement("a");
    link.setAttribute("href", encodedUri);
    link.setAttribute("download", "peregrinos_lujaneta_" + new Date().toISOString().slice(0,10) + ".csv");
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
};
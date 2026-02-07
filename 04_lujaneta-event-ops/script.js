// ============================================================
// CONFIGURACIÓN DE SUPABASE
// ============================================================
const SUPABASE_URL = 'https://xsutpmbhvzuvjpwwyoli.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzdXRwbWJodnp1dmpwd3d5b2xpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAzNzUwNTMsImV4cCI6MjA4NTk1MTA1M30.ym7wCHRwpit-4OaHM9V3JSzbR-baH1WfEYIAFfbAgBo';

const supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

const EVENT_ID = '6467bce4-6ff5-44cf-b591-7463ad9c92cf';

// ============================================================
// LÓGICA DEL FORMULARIO
// ============================================================
const form = document.getElementById('registrationForm');
const statusDiv = document.getElementById('status');
const submitBtn = form.querySelector('button[type="submit"]');

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  
  submitBtn.disabled = true;
  submitBtn.textContent = 'Procesando inscripción...';
  statusDiv.textContent = 'Iniciando carga de datos...';
  statusDiv.style.color = 'blue';

  try {
    const formData = new FormData(form);

    // --------------------------------------------------------
    // PASO 1: Subir Comprobante (Storage)
    // --------------------------------------------------------
    let proof_file_url = null;
    const file = formData.get('proof_file');

    if (file && file.size > 0) {
      statusDiv.textContent = 'Subiendo comprobante de pago...';
      
      const fileExt = file.name.split('.').pop();
      const fileName = `proofs/${Date.now()}_${Math.floor(Math.random() * 1000)}.${fileExt}`;

      const { data: storageData, error: storageError } = await supabaseClient.storage
        .from('payments') 
        .upload(fileName, file);

      if (storageError) throw new Error(`Error subiendo archivo: ${storageError.message}`);

      const { data: urlData } = supabaseClient.storage
        .from('payments')
        .getPublicUrl(storageData.path);
        
      proof_file_url = urlData.publicUrl;
    }

    // --------------------------------------------------------
    // PASO 2: Gestionar Participante (Buscar o Crear)
    // --------------------------------------------------------
    statusDiv.textContent = 'Verificando datos personales...';

    const docType = formData.get('doc_type');
    const docNumber = formData.get('doc_number');
    
    // Captura correcta de los Radio Buttons
    const medicalFlag = formData.get('medical_flag') === 'true'; 
    const allergiesFlag = formData.get('allergies_flag') === 'true';

    let participantId = null;

    // A. Buscamos si ya existe
    const { data: existingUser, error: searchError } = await supabaseClient
      .from('participants')
      .select('participant_id')
      .eq('doc_type', docType)
      .eq('doc_number', docNumber)
      .maybeSingle(); 

    if (searchError) throw new Error(`Error buscando usuario: ${searchError.message}`);

    if (existingUser) {
        // SI YA EXISTE: Usamos su ID
        console.log("Usuario existente encontrado, usando ID:", existingUser.participant_id);
        participantId = existingUser.participant_id;
    } else {
        // SI NO EXISTE: Lo creamos
        const { data: newUser, error: createError } = await supabaseClient
          .from('participants')
          .insert({
            full_name: formData.get('full_name'),
            doc_type: docType,
            doc_number: docNumber,
            birthdate: formData.get('birthdate'),
            phone: formData.get('phone'),
            email: formData.get('email'),
            emergency_contact_name: formData.get('emergency_contact_name'),
            emergency_contact_phone: formData.get('emergency_contact_phone'),
            medical_flag: medicalFlag,
            medical_notes: formData.get('medical_notes'),
            allergies_flag: allergiesFlag,
            allergies_notes: formData.get('allergies_notes')
          })
          .select()
          .single();

        if (createError) throw new Error(`Error creando participante: ${createError.message}`);
        participantId = newUser.participant_id;
    }

    // --------------------------------------------------------
    // PASO 3: Gestionar Inscripción (Buscar o Crear)
    // --------------------------------------------------------
    statusDiv.textContent = 'Registrando en el evento...';
    let registrationId = null;

    // A. Buscamos si ya está inscrito en ESTE evento
    const { data: existingReg, error: searchRegError } = await supabaseClient
        .from('registrations')
        .select('registration_id')
        .eq('participant_id', participantId)
        .eq('event_id', EVENT_ID)
        .maybeSingle();

    if (existingReg) {
        registrationId = existingReg.registration_id;
    } else {
        const { data: newReg, error: regError } = await supabaseClient
          .from('registrations')
          .insert({
            participant_id: participantId,
            event_id: EVENT_ID,
            experience: formData.get('experience'),
            fitness: formData.get('fitness'),
            departure: formData.get('departure'),
            payment_status: 'Submitted',
            field_status: 'NotCheckedIn',
            role: 'Participant'
          })
          .select()
          .single();

        if (regError) throw new Error(`Error en inscripción: ${regError.message}`);
        registrationId = newReg.registration_id;
    }

    // --------------------------------------------------------
    // PASO 4: Registrar Pago
    // --------------------------------------------------------
    statusDiv.textContent = 'Procesando pago...';

    const { error: payError } = await supabaseClient
      .from('payments')
      .insert({
        registration_id: registrationId,
        method: formData.get('payment_method'),
        amount: parseFloat(formData.get('amount')),
        proof_file_url: proof_file_url,
        status: 'Submitted'
      });

    if (payError) throw new Error(`Error registrando pago: ${payError.message}`);

    // --------------------------------------------------------
    // MENSAJE DE ÉXITO DETALLADO
    // --------------------------------------------------------
    statusDiv.innerHTML = `
        <h3 style="margin-top:0">¡Inscripción Recibida! ✅</h3>
        <p>Hemos recibido tus datos y el comprobante de pago.</p>
        <p><strong>¿Qué sigue?</strong><br>
        1. El equipo de Finanzas verificará tu transferencia.<br>
        2. Una vez aprobado, te enviaremos el <strong>CÓDIGO QR</strong> a tu email: <em>${formData.get('email')}</em>.<br>
        3. <strong>IMPORTANTE:</strong> Guarda ese QR (captura o archivo). Sin él no podrás retirar tu kit ni recibir asistencia del grupo.</p>
    `;
    statusDiv.style.color = '#27ae60';
    statusDiv.style.backgroundColor = '#e8f8f5';
    statusDiv.style.border = '1px solid #2ecc71';
    
    form.reset();
    document.getElementById('medical_notes').classList.remove('visible');
    document.getElementById('allergies_notes').classList.remove('visible');

  } catch (err) {
    console.error(err);
    statusDiv.textContent = "Error: " + err.message;
    statusDiv.style.color = 'red';
  } finally {
    submitBtn.disabled = false;
    submitBtn.textContent = 'CONFIRMAR INSCRIPCIÓN';
  }
});
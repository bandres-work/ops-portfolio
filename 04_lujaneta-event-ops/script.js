// ================= CONFIGURACIÓN =================
const SUPABASE_URL = 'https://xsutpmbhvzuvjpwwyoli.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzdXRwbWJodnp1dmpwd3d5b2xpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAzNzUwNTMsImV4cCI6MjA4NTk1MTA1M30.ym7wCHRwpit-4OaHM9V3JSzbR-baH1WfEYIAFfbAgBo';

// ID DEL EVENTO (Sacado de tu tabla 'events')
const EVENT_ID = '6467bce4-6ff5-44cf-b591-7463ad9c92cf'; 

const supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

console.log("⚡ Script vFinal 2.0 cargado.");

document.getElementById('registrationForm').addEventListener('submit', async (e) => {
    e.preventDefault(); 
    
    // UI Elements
    const submitBtn = document.getElementById('submitBtn');
    const statusDiv = document.getElementById('status');
    const successMsg = document.getElementById('successMessage');
    const form = document.getElementById('registrationForm');

    // Bloqueo botón
    submitBtn.disabled = true;
    submitBtn.textContent = "Procesando...";
    statusDiv.innerHTML = "⏳ Conectando...";
    statusDiv.style.color = "blue";

    try {
        // --- 1. RECOLECTAR DATOS ---
        const fullName = document.getElementById('fullName').value;
        const docType = document.getElementById('docType').value;
        const dni = document.getElementById('dni').value;
        const birthDate = document.getElementById('birthDate').value;
        const phone = document.getElementById('phone').value;
        const email = document.getElementById('email').value;
        
        const emergencyName = document.getElementById('emergencyName').value;
        const emergencyPhone = document.getElementById('emergencyPhone').value;
        
        const medicalInput = document.querySelector('input[name="medicalCond"]:checked').value;
        const medicalText = document.getElementById('medicalText').value;
        const medicalFlag = medicalInput === 'si';
        
        const allergiesInput = document.querySelector('input[name="allergies"]:checked').value;
        const allergiesText = document.getElementById('allergyText').value;
        const allergiesFlag = allergiesInput === 'si';
        
        const experience = document.getElementById('experience').value;
        const fitness = document.getElementById('fitness').value;
        const departure = document.getElementById('departure').value;
        
        const paymentMethod = document.getElementById('paymentMethod').value;
        const amountPaid = document.getElementById('amountPaid').value;
        const paymentFile = document.getElementById('paymentProof').files[0];

        if (!paymentFile) throw new Error("Debes subir el comprobante de pago.");

        // --- 2. SUBIR FOTO ---
        statusDiv.innerHTML = "📤 Subiendo foto...";
        const fileName = `${Date.now()}_${dni}`;
        
        const { data: fileData, error: fileError } = await supabaseClient.storage
            .from('payments') 
            .upload(fileName, paymentFile);

        if (fileError) throw new Error("Error al subir foto: " + fileError.message);

        const { data: urlData } = supabaseClient.storage.from('payments').getPublicUrl(fileName);
        const publicUrl = urlData.publicUrl;

        // --- 3. GESTIÓN DE PARTICIPANTE ---
        statusDiv.innerHTML = "👤 Verificando usuario...";
        
        // Buscar si existe por DNI
        const { data: existingUser, error: searchError } = await supabaseClient
            .from('participants')
            .select('participant_id')
            .eq('doc_number', dni)
            .maybeSingle();

        if (searchError) throw new Error("Error buscando usuario: " + searchError.message);

        let participantId = null;

        const participantData = {
            full_name: fullName, 
            doc_type: docType,
            doc_number: dni, 
            birthdate: birthDate,
            phone: phone,
            email: email, 
            emergency_contact_name: emergencyName,   
            emergency_contact_phone: emergencyPhone,
            medical_flag: medicalFlag,
            medical_notes: medicalFlag ? medicalText : "Ninguna",
            allergies_flag: allergiesFlag,
            allergies_notes: allergiesFlag ? allergiesText : "Ninguna"
        };

        if (existingUser) {
            console.log("Usuario existente. Actualizando...");
            const { error: updateError } = await supabaseClient
                .from('participants')
                .update(participantData)
                .eq('participant_id', existingUser.participant_id);
            
            if (updateError) throw new Error("Error actualizando usuario: " + updateError.message);
            participantId = existingUser.participant_id;

        } else {
            console.log("Usuario nuevo. Creando...");
            const { data: newUser, error: insertError } = await supabaseClient
                .from('participants')
                .insert(participantData)
                .select('participant_id')
                .single();
            
            if (insertError) throw new Error("Error creando usuario: " + insertError.message);
            participantId = newUser.participant_id;
        }

        // --- 4. GUARDAR INSCRIPCIÓN ---
        statusDiv.innerHTML = "📝 Creando ficha...";
        
        const { data: registration, error: regError } = await supabaseClient
            .from('registrations')
            .insert({
                participant_id: participantId,
                event_id: EVENT_ID,         // <--- AQUÍ ESTABA EL ERROR (Faltaba esto)
                role: 'Participant',
                departure: departure,
                experience: experience, 
                fitness: fitness,       
                kit: 'Eligible',
                notes_ops: `Pago: ${paymentMethod}`,
                payment_verified_at: null,
                checked_in: false
            })
            .select()
            .single();

        if (regError) throw new Error("Error creando registro: " + regError.message);

        // --- 5. GUARDAR PAGO ---
        statusDiv.innerHTML = "💰 Finalizando...";
        
        const { error: payError } = await supabaseClient
            .from('payments')
            .insert({
                registration_id: registration.registration_id,
                amount: amountPaid,
                method: paymentMethod,
                currency: 'ARS',
                proof_file_url: publicUrl,
                status: 'Submitted'
            });

        if (payError) throw new Error("Error guardando pago: " + payError.message);

        // --- 6. ÉXITO ---
        console.log("✅ Éxito total");
        statusDiv.innerHTML = ""; 
        
        Array.from(form.children).forEach(child => {
            if (child.id !== 'successMessage') child.style.display = 'none';
        });
        
        successMsg.style.display = 'block';
        window.scrollTo({ top: 0, behavior: 'smooth' });

    } catch (error) {
        console.error("❌ ERROR:", error);
        statusDiv.innerHTML = `
            <div style="background:#fee2e2; color:#b91c1c; padding:15px; border-radius:8px; border:1px solid #fca5a5; margin-top:15px; text-align:center;">
                <h3>⛔ Error</h3>
                <p>${error.message}</p>
            </div>
        `;
        submitBtn.disabled = false;
        submitBtn.textContent = "Reintentar";
    }
});
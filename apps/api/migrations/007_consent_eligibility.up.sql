CREATE FUNCTION required_consents_completed(target_user UUID) RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
 SELECT EXISTS(SELECT 1 FROM consent_documents WHERE active AND required)
 AND NOT EXISTS(
  SELECT 1 FROM consent_documents d
  LEFT JOIN LATERAL (
   SELECT decision,document_version FROM user_consents
   WHERE user_id=target_user AND consent_type=d.consent_type
   ORDER BY sequence DESC LIMIT 1
  ) c ON true
  WHERE d.active AND d.required AND
   (c.decision IS DISTINCT FROM 'accepted' OR c.document_version IS DISTINCT FROM d.document_version)
 );
$$;

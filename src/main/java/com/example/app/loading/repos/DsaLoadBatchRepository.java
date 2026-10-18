package com.example.app.loading.repos;

import org.springframework.data.jpa.repository.JpaRepository;

import com.example.app.loading.models.DsaLoadBatch;

public interface DsaLoadBatchRepository extends JpaRepository<DsaLoadBatch, Long> {}

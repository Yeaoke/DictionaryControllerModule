package com.example.app.repos;

import org.springframework.data.jpa.repository.JpaRepository;

import com.example.app.models.DsaLoadBatch;

public interface DsaLoadBatchRepository extends JpaRepository<DsaLoadBatch, Long> {}
